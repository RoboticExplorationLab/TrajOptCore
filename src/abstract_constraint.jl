# export
# 	ConstraintSense,
# 	Inequality,
# 	Equality,
# 	Stage,
# 	State,
# 	Control,
# 	Coupled,
# 	Dynamical
#
# export
# 	evaluate,
# 	jacobian

import RobotDynamics: jacobian!


"Specifies whether the constraint is an equality or inequality constraint.
Valid subtypes are `Equality`, `Inequality`, and `Null`"
abstract type ConstraintSense end
"Inequality constraints of the form ``h(x) \\leq 0``"
struct Equality <: ConstraintSense end
"Equality constraints of the form ``g(x) = 0``"
struct Inequality <: ConstraintSense end


"""
	AbstractConstraint

Abstract vector-valued constraint of size `P` for a trajectory optimization problem.
May be either inequality or equality (specified by `S<:ConstraintSense`), and be function of
single, adjacent, or all knotpoints (specified by `W<:ConstraintType`).

Interface:
Any constraint type must implement the following interface:
```julia
n = state_dim(::MyCon)
m = control_dim(::MyCon)
p = Base.length(::MyCon)
c = evaluate(::MyCon, args...)   # args determined by W
∇c = jacobian(::MyCon, args...)  # args determined by W
```

The `evaluate` and `jacobian` (identical signatures) methods should have the following signatures
* W <: State: `evaluate(::MyCon, x::SVector)`
* W <: Control: `evaluate(::MyCon, u::SVector)`
* W <: Stage: `evaluate(::MyCon, x, u)`
* W <: Dynamical: `evaluate(::MyCon, x′, x, u)`
* W <: Coupled: `evaluate(::MyCon, x′, u′ x, u)`

Or alternatively,
* W <: Stage: `evaluate(::MyCon, z::KnotPoint)`
* W <: Coupled: `evaluate(::MyCon, z′::KnotPoint, z::KnotPoint)`

The Jacobian method for [`State`](@ref) or [`Control`](@ref) is optional, since it will
	be automatically computed using ForwardDiff. Automatic differentiation
	for other types of constraints is not yet supported.

For W <: State, `control_dim(::MyCon)` doesn't need to be defined. Equivalently, for
	W <: Control, `state_dim(::MyCon)` doesn't need to be defined.

For W <: General, the more general `evaluate` and `jacobian` methods must be used
```julia
evaluate!(vals::Vector{<:AbstractVector}, ::MyCon, Z::Traj, inds=1:length(Z)-1)
jacobian!(∇c::Vector{<:AbstractMatrix}, ::MyCon, Z::Traj, inds=1:length(Z)-1)
```
These methods can be specified for any constraint, instead of the not-in-place functions
	above.
"""
abstract type AbstractConstraint end

"Only a function of states and controls at a single knotpoint"
abstract type StageConstraint <: AbstractConstraint end
"Only a function of states at a single knotpoint"
abstract type StateConstraint <: StageConstraint end
"Only a function of controls at a single knotpoint"
abstract type ControlConstraint <: StageConstraint end
"Only a function of states and controls at two adjacent knotpoints"
abstract type CoupledConstraint <: AbstractConstraint end
"Only a function of states at adjacent knotpoints"
abstract type CoupledStateConstraint <: CoupledConstraint end
"Only a function of controls at adjacent knotpoints"
abstract type CoupledControlConstraint <: CoupledConstraint end

const StateConstraints = Union{StageConstraint, StateConstraint, CoupledConstraint, CoupledStateConstraint}
const ControlConstraints = Union{StageConstraint, ControlConstraint, CoupledConstraint, CoupledControlConstraint}

"Get constraint sense (Inequality vs Equality)"
sense(::C) where C <: AbstractConstraint = throw(NotImplemented(:sense, Symbol(C)))
"Get type of constraint (bandedness)"
contype(::C) where C <: AbstractConstraint = throw(NotImplemented(:contype, Symbol(C)))
"Dimension of the state vector"
RobotDynamics.state_dim(::C) where C <: StateConstraint = throw(NotImplemented(:state_dim, Symbol(C)))
"Dimension of the control vector"
RobotDynamics.control_dim(::C) where C <: ControlConstraint = throw(NotImplemented(:control_dim, Symbol(C)))
"Return the constraint value"
evaluate(::C) where C <: AbstractConstraint = throw(NotImplemented(:evaluate, Symbol(C)))
"Length of constraint vector"
Base.length(::C) where C <: AbstractConstraint = throw(NotImplemented(:length, Symbol(C)))

Base.size(con::AbstractConstraint) = (length(con), width(con))

"Returns the width of the constraint Jacobian, i.e. the total number of inputs
to the constraint"
width(con::AbstractConstraint) = sum(widths(con))

width(::StageConstraint,n,m) = n+m
width(::StateConstraint,n,m) = n
width(::ControlConstraint,n,m) = m
width(::CoupledConstraint,n,m) = 2n + 2m
width(::CoupledStateConstraint,n,m) = 2n
width(::CoupledControlConstraint,n,m) = 2m

widths(con::StageConstraint) = (state_dim(con) + control_dim(con),)
widths(con::StateConstraint) = (state_dim(con),)
widths(con::ControlConstraint) = (control_dim(con),)
widths(con::CoupledConstraint) = (state_dim(con) + control_dim(con), state_dim(con) + control_dim(con))
widths(con::CoupledStateConstraint) = (state_dim(con), state_dim(con))
widths(con::CoupledControlConstraint) = (control_dim(con), control_dim(con))

"Upper bound of the constraint, as a vector, which is 0 for all constraints
(except bound constraints)"
@inline upper_bound(con::AbstractConstraint) = upper_bound(sense(con)) * @SVector ones(length(con))
@inline upper_bound(::Inequality) = 0.0
@inline upper_bound(::Equality) = 0.0

"Upper bound of the constraint, as a vector, which is 0 equality and -Inf for inequality
(except bound constraints)"
@inline lower_bound(con::AbstractConstraint) = lower_bound(sense(con)) * @SVector ones(length(con))
@inline lower_bound(::Inequality) = -Inf
@inline lower_bound(::Equality) = 0.0

"Is the constraint a bound constraint or not"
@inline is_bound(con::AbstractConstraint) = false

"Check whether the constraint is consistent with the specified state and control dimensions"
@inline check_dims(con::StateConstraint,n,m) = state_dim(con) == n
@inline check_dims(con::ControlConstraint,n,m) = control_dim(con) == m
@inline check_dims(con::AbstractConstraint,n,m) = state_dim(con) == n && control_dim(con) == m

con_label(::AbstractConstraint, i::Int) = "index $i"

############################################################################################
# 								EVALUATION METHODS 										   #
############################################################################################
"""```
evaluate!(vals::Vector{<:AbstractVector}, con::AbstractConstraint{S,W,P},
	Z, inds=1:length(Z)-1)
```
Evaluate constraints for entire trajectory. This is the most general method used to evaluate
	constraints, and should be the one used in other functions.

For W<:Stage this will loop over calls to `evaluate(con,Z[k])`

For W<:Coupled this will loop over calls to `evaluate(con,Z[k+1],Z[k])`

For W<:General,this must function must be explicitly defined. Other types may define it
	if desired.
"""
function evaluate!(vals::Vector{<:AbstractVector}, con::StageConstraint,
		Z::Traj, inds=1:length(Z))
	for (i,k) in enumerate(inds)
		vals[i] = evaluate(con, Z[k])
	end
end

function evaluate!(vals::Vector{<:AbstractVector}, con::CoupledConstraint,
		Z::Traj, inds=1:length(Z)-1)
	for (i,k) in enumerate(inds)
		vals[i] = evaluate(con, Z[k+1], Z[k])
	end
end

"""```
jacobian!(vals::Vector{<:AbstractVector}, con::AbstractConstraint{S,W,P},
	Z, inds=1:length(Z)-1)
```
Evaluate constraint Jacobians for entire trajectory. This is the most general method used to
	evaluate constraint Jacobians, and should be the one used in other functions.

For W<:Stage this will loop over calls to `jacobian(con,Z[k])`

For W<:Coupled this will loop over calls to `jacobian(con,Z[k+1],Z[k])`

For W<:General,this must function must be explicitly defined. Other types may define it
	if desired.
"""
function jacobian!(∇c::VecOrMat{<:AbstractMatrix}, con::StageConstraint,
		Z::Traj, inds=1:length(Z))
	for (i,k) in enumerate(inds)
		jacobian!(∇c[i], con, Z[k], 1)
	end
end

function jacobian!(∇c::VecOrMat{<:AbstractMatrix}, con::CoupledConstraint,
		Z::Traj, inds=1:length(Z))
	for (i,k) in enumerate(inds)
		jacobian!(∇c[i], con, Z[k+1], Z[k], 1)
		jacobian!(∇c[i], con, Z[k+1], Z[k], 2)
	end
end

# Default methods for converting KnotPoints to states and controls for StageConstraints
@inline evaluate(con::StateConstraint, z::AbstractKnotPoint) = evaluate(con, state(z))
@inline evaluate(con::ControlConstraint, z::AbstractKnotPoint) = evaluate(con, control(z))
@inline evaluate(con::StageConstraint, z::AbstractKnotPoint) = evaluate(con, state(z), control(z))

@inline jacobian!(∇c, con::StateConstraint, z::AbstractKnotPoint, i=1) =
	jacobian!(∇c, con, state(z))
@inline jacobian!(∇c, con::ControlConstraint, z::AbstractKnotPoint, i=1) =
	jacobian!(∇c, con, control(z))
@inline jacobian!(∇c, con::StageConstraint, z::AbstractKnotPoint, i=1) =
	jacobian!(∇c, con, state(z), control(z))

# ForwardDiff jacobians that are of only state or control
function jacobian!(∇c, con::Union{StageConstraint,ControlConstraint}, x::StaticVector)
	eval_c(x) = evaluate(con, x)
	∇c .= ForwardDiff.jacobian(eval_c, x)
	return false
end

function jacobian!(∇c, con::StageConstraint, z::AbstractKnotPoint)
	eval_c(x) = evaluate(con, StaticKnotPoint(z, x))
	∇c .= ForwardDiff.jacobian(eval_c, z.z)
	return false
end

@inline gen_jacobian(con::AbstractConstraint) = SizedMatrix{size(con)...}(zeros(size(con)))

############################################################################################
#					             CONSTRAINT LIST										   #
############################################################################################
struct ConstraintList
	n::Int
	m::Int
	constraints::Vector{AbstractConstraint}
	inds::Vector{UnitRange{Int}}
	p::Vector{Int}
	function ConstraintList(n::Int, m::Int, N::Int)
		constraints = AbstractConstraint[]
		inds = UnitRange{Int}[]
		p = zeros(Int,N)
		new(n, m, constraints, inds, p)
	end
end

function add_constraint!(cons::ConstraintList, con::AbstractConstraint, inds::UnitRange{Int}, idx=-1)
	@assert check_dims(con, cons.n, cons.m) "New constaint not consistent with n=$(cons.n) and m=$(cons.m)"
	@assert inds[end] <= length(cons.p) "Invalid inds, inds[end] must be less than number of knotpoints, $(length(cons.p))"
	if idx == -1
		push!(cons.constraints, con)
		push!(cons.inds, inds)
	elseif 0 < idx <= length(cons)
		insert!(cons.constraints, idx, con)
		insert!(cons.inds, idx, inds)
	else
		throw(ArgumentError("cannot insert constraint at index=$idx. Length = $(length(cons))"))
	end
	@assert length(cons.constraints) == length(cons.inds)
end

@inline add_constraint!(cons::ConstraintList, con::AbstractConstraint, k::Int, idx=-1) =
	add_constraint!(cons, con, k:k, idx)

@inline Base.length(cons::ConstraintList) = length(cons.constraints)

@inline Base.getindex(cons::ConstraintList, i::Int) = cons.constraints[i]
