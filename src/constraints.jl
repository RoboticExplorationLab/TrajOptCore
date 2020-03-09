export
	GoalConstraint,
	BoundConstraint,
	CircleConstraint,
	SphereConstraint,
	NormConstraint,
	LinearConstraint,
	VariableBoundConstraint,
	QuatNormConstraint,
	QuatSlackConstraint



############################################################################################
#                              GOAL CONSTRAINTS 										   #
############################################################################################

"""
$(TYPEDEF)
Constraint of the form ``x_g = a``, where ``x_g`` can be only part of the state
vector.

# Constructors:
```julia
GoalConstraint(xf::AbstractVector)
GoalConstraint(xf::AbstractVector, inds)
```
where `xf` is an n-dimensional goal state. If `inds` is provided,
only `xf[inds]` will be used.
"""
struct GoalConstraint{T,P,N,L} <: AbstractConstraint{Equality,State,P}
	xf::SVector{P,T}
	Ix::SMatrix{P,N,T,L}
	inds::SVector{P,Int}
end

function GoalConstraint(xf::AbstractVector, inds=1:length(xf))
	n = length(xf)
	p = length(inds)
	xf = SVector{n}(xf)
	inds = SVector{p}(inds)
	GoalConstraint(xf, inds)
end

function GoalConstraint(xf::SVector{n}, inds::SVector{p,Int}) where {n,p}
	Ix = SMatrix{n,n}(Matrix(1.0I,n,n))
	Ix = Ix[inds,:]
	GoalConstraint(SVector{p}(xf[inds]), Ix, inds)
end

state_dim(::GoalConstraint{T,P,N}) where {T,P,N} = N
evaluate(con::GoalConstraint, x::SVector) = x[con.inds] - con.xf
jacobian(con::GoalConstraint, z::KnotPoint) = con.Ix


############################################################################################
#                              LINEAR CONSTRAINTS 										   #
############################################################################################
"""
$(TYPEDEF)
Linear constraint of the form ``Ay - b \\{\\leq,=\\} 0`` where ``y`` may be either the
state or controls (but not a combination of both).

# Constructor: ```julia
LinearConstraint{S,W}(n,m,A,b)
```
where `W <: Union{State,Control}`.
"""
struct LinearConstraint{S,W<:Union{State,Control},P,N,L,T} <: AbstractConstraint{S,W,P}
	n::Int
	m::Int
	A::SMatrix{P,N,T,L}
	b::SVector{P,T}
end

function LinearConstraint{S,W}(n,m, A::AbstractMatrix, b::AbstractVector) where {S,W}
	@assert size(A,1) == length(b)
	p,q = size(A)
	A = SMatrix{p,q}(A)
	b = SVector{p}(b)
	LinearConstraint{S,W}(n,m, A, b)
end

function LinearConstraint{S,W}(n::Int,m::Int, A::SMatrix{P,N,T}, b::SVector{P,T}) where {S,W,P,N,T}
	con = LinearConstraint{S,W,P,N,P*N,T}(n,m,A,b)
	@assert check_dims(con,n,m) "Dimensions of LinearConstraint are inconsistent"
	return con
end

state_dim(::LinearConstraint{S,State,P,N}) where {S,P,N} = N
control_dim(::LinearConstraint{S,Control,P,N}) where {S,P,N} = N
evaluate(con::LinearConstraint,x::SVector) = con.A*x - con.b
jacobian(con::LinearConstraint,x::SVector) = con.A



############################################################################################
#                              CIRCLE/SPHERE CONSTRAINTS 								   #
############################################################################################
"""
$(TYPEDEF)
Constraint of the form
`` (x - x_c)^2 + (y - y_c)^2 \\leq r^2 ``
where ``x``, ``y`` are given by `x[xi]`,`x[yi]`, ``(x_c,y_c)`` is the center
of the circle, and ``r`` is the radius.

# Constructor:
```julia
CircleConstraint(n, xc::SVector{P}, yc::SVector{P}, radius::SVector{P}, xi=1, yi=2)
```
"""
struct CircleConstraint{T,P} <: AbstractConstraint{Inequality,State,P}
	n::Int
	x::SVector{P,T}
	y::SVector{P,T}
	radius::SVector{P,T}
	xi::Int  # index of x-state
	yi::Int  # index of y-state
	CircleConstraint(n::Int, xc::SVector{P,T}, yc::SVector{P,T}, radius::SVector{P,T},
			xi=1, yi=2) where {T,P} =
		 new{T,P}(n,xc,yc,radius,xi,yi)
end
state_dim(con::CircleConstraint) = con.n

function evaluate(con::CircleConstraint{T,P}, x::SVector) where {T,P}
	xc = con.x; xi = con.xi
	yc = con.y; yi = con.yi
	r = con.radius
	-(x[xi] .- xc).^2 - (x[yi] .- yc).^2 + r.^2
end


"""
$(TYPEDEF)
Constraint of the form
`` (x - x_c)^2 + (y - y_c)^2 + (z - z_c)^2 \\leq r^2 ``
where ``x``, ``y``, ``z`` are given by `x[xi]`,`x[yi]`,`x[zi]`, ``(x_c,y_c,z_c)`` is the center
of the sphere, and ``r`` is the radius.

# Constructor:
```
SphereConstraint(n, xc::SVector{P}, yc::SVector{P}, zc::SVector{P},
	radius::SVector{P}, xi=1, yi=2, zi=3)
```
"""
struct SphereConstraint{T,P} <: AbstractConstraint{Inequality,State,P}
	n::Int
	x::SVector{P,T}
	y::SVector{P,T}
	z::SVector{P,T}
	xi::Int
	yi::Int
	zi::Int
	radius::SVector{P,T}
	SphereConstraint(n::Int, xc::SVector{P,T}, yc::SVector{P,T}, zc::SVector{P,T},
			radius::SVector{P,T}, xi=1, yi=2, zi=3) where {T,P} =
			new{T,P}(n,xc,yc,zc,xi,yi,zi,radius)
end

state_dim(con::SphereConstraint) = con.n

function evaluate(con::SphereConstraint{T,P}, x::SVector) where {T,P}
	xc = con.x; xi = con.xi
	yc = con.y; yi = con.yi
	zc = con.z; zi = con.zi
	r = con.radius

	-((x[xi] .- xc).^2 + (x[yi] .- yc).^2 + (x[zi] .- zc).^2 - r.^2)
end

############################################################################################
#  								SELF-COLLISION CONSTRAINT 								   #
############################################################################################

struct CollisionConstraint{D} <: AbstractConstraint{Inequality,State,1}
	n::Int
    x1::SVector{D,Int}
    x2::SVector{D,Int}
    radius::Float64
end

state_dim(con::CollisionConstraint) = con.n

function evaluate(con::CollisionConstraint, x::SVector)
    x1 = x[con.x1]
    x2 = x[con.x2]
    d = x1 - x2
    @SVector [con.radius^2 - d'd]
end

############################################################################################
#								NORM CONSTRAINT											   #
############################################################################################

"""
$(TYPEDEF)
Constraint of the form
``\\|y\\|^2 \\{\\leq,=\\} a``
where ``y`` is either a state or a control vector (but not both)

# Constructors:
```
NormConstraint{S,State}(n,a)
NormConstraint{S,Control}(m,a)
```
where `a` is the constant on the right-hand side of the equation.

# Examples:
```julia
NormConstraint{Equality,Control}(2,4.0)
```
creates a constraint equivalent to
``\\|u\\|^2 = 4.0`` for a problem with 2 controls.

```julia
NormConstraint{Inequality,State}(3, 2.3)
```
creates a constraint equivalent to
``\\|x\\|^2 \\leq 2.3`` for a problem with 3 states.
"""
struct NormConstraint{S,W<:Union{State,Control},T} <: AbstractConstraint{S,W,1}
	dim::Int
	val::T
	function NormConstraint{S,W,T}(dim::Int, val::T) where {S,W<:Union{State,Control},T}
		@assert val ≥ 0 "Value must be greater than or equal to zero"
		new{S,W,T}(dim, val)
	end
end
NormConstraint{S,W}(n::Int, val::T) where {S,W,T} = NormConstraint{S,W,T}(n, val)

state_dim(con::NormConstraint{S,State}) where S = con.dim
control_dim(con::NormConstraint{S,Control}) where S = con.dim

function evaluate(con::NormConstraint, x::SVector)
	return @SVector [norm(x)^2 - con.val]
end

struct QuatNormConstraint <: AbstractConstraint{Equality,State,1}
	n::Int
	qinds::SVector{4,Int}
end

QuatNormConstraint(n::Int=13, qinds=(@SVector [4,5,6,7])) = QuatNormConstraint(n, qinds)

state_dim(con::QuatNormConstraint) = con.n

function evaluate(con::QuatNormConstraint, x::SVector)
	q = x[con.qinds]
	return @SVector [norm(q) - 1.0]
end

struct QuatSlackConstraint <: AbstractConstraint{Equality,Stage,1}
	qinds::SVector{4,Int}
end
(::Type{<:QuatSlackConstraint})(qinds=(@SVector [4,5,6,7])) = QuatSlackConstraint(qinds)

state_dim(::QuatSlackConstraint) = 13
control_dim(::QuatSlackConstraint) = 5  # special cased for quadrotor

function evaluate(con::QuatSlackConstraint, x::SVector, u::SVector)
	s = u[end]
	q = x[con.qinds]
	return @SVector [norm(q)*s - 1.0]
end

function jacobian(con::QuatSlackConstraint, x::SVector, u::SVector)
	s = u[end]
	q = x[con.qinds]
	nq = norm(q)
	M = s/nq
	return @SMatrix [0 0 0 q[1]*M  q[2]*M  q[3]*M  q[4]*M  0 0 0  0 0 0  0 0 0 0 nq]
end

############################################################################################
# 								COPY CONSTRAINT 										   #
############################################################################################

# struct CopyConstraint{K,W,S,P,N,M} <: AbstractConstraint{W,S,P}
# 	con::AbstractConstraint{W,S,P}
#     xinds::Vector{SVector{N,Int}}
#     uinds::Vector{SVector{M,Int}}
# end
#
# function evaluate(con::CopyConstraint{K}, z::KnotPoint)
# 	c = evaluate(con,)
# 	for 2 = 1:K
# 	end
# end


############################################################################################
# 								BOUND CONSTRAINTS 										   #
############################################################################################
"""$(TYPEDEF) Linear bound constraint on states and controls
# Constructors
```julia
BoundConstraint(n, m; x_min, x_max, u_min, u_max)
```
Any of the bounds can be ±∞. The bound can also be specifed as a single scalar, which applies the bound to all state/controls.
"""
struct BoundConstraint{T,P,NM,PNM} <: AbstractConstraint{Inequality,Stage,P}
	n::Int
	m::Int
	z_max::SVector{NM,T}
	z_min::SVector{NM,T}
	b::SVector{P,T}
	B::SMatrix{P,NM,T,PNM}
	inds::SVector{P,Int}
end

function BoundConstraint(n, m; x_max=Inf*(@SVector ones(n)), x_min=-Inf*(@SVector ones(n)),
		u_max=Inf*(@SVector ones(m)), u_min=-Inf*(@SVector ones(m)))
	# Check and convert bounds
	x_max, x_min = checkBounds(Val(n), x_max, x_min)
	u_max, u_min = checkBounds(Val(m), u_max, u_min)

	# Concatenate bounds
	z_max = [x_max; u_max]
	z_min = [x_min; u_min]
	b = [-z_max; z_min]
	bN = [x_max; u_max*Inf; x_min; -u_min*Inf]

	active = isfinite.(b)
	p = sum(active)
	inds = SVector{p}(findall(active))

	B = SMatrix{2(n+m), n+m}([1.0I(n+m); -1.0I(n+m)])

	BoundConstraint(n, m, z_max, z_min, b[inds], B[inds,:], inds)
end

function con_label(con::BoundConstraint, ind::Int)
	i = con.inds[ind]
	n,m = state_dim(con), control_dim(con)
	if 1 <= i <= n
		return "x max $i"
	elseif n < i <= n + m
		j = i - n
		return "u max $j"
	elseif n + m < i <= 2n+m
		j = i - (n+m)
		return "x min $j"
	elseif 2n+m < i <= 2n+2m
		j = i - (2n+m)
		return "u min $j"
	else
		throw(BoundsError())
	end
end

function checkBounds(::Val{N}, u::AbstractVector, l::AbstractVector) where N
	if all(u .>= l)
		return SVector{N}(u), SVector{N}(l)
	else
		throw(ArgumentError("Upper bounds must be greater than or equal to lower bounds"))
	end
end

checkBounds(sze::Val{N}, u::Real, l::Real) where N =
	checkBounds(sze, (@SVector fill(u,N)), (@SVector fill(l,N)))
checkBounds(sze::Val{N}, u::AbstractVector, l::Real) where N =
	checkBounds(sze, u, (@SVector fill(l,N)))
checkBounds(sze::Val{N}, u::Real, l::AbstractVector) where N =
	checkBounds(sze, (@SVector fill(u,N)), l)


state_dim(con::BoundConstraint) = con.n
control_dim(con::BoundConstraint) = con.m
is_bound(::BoundConstraint) = true
lower_bound(bnd::BoundConstraint) = bnd.z_min
upper_bound(bnd::BoundConstraint) = bnd.z_max


function evaluate(bnd::BoundConstraint{T,P,NM}, x, u) where {T,P,NM}
	bnd.B*SVector{NM}([x; u]) + bnd.b
end

function jacobian!(∇c, bnd::BoundConstraint, z::AbstractKnotPoint)
	∇c .= bnd.B
end


############################################################################################
#  							VARIABLE BOUND CONSTRAINT 									   #
############################################################################################

struct VariableBoundConstraint{T,P,NM,PNM} <: AbstractConstraint{Inequality,Stage,P}
	n::Int
	m::Int
	z_max::Vector{SVector{NM,T}}
	z_min::Vector{SVector{NM,T}}
	b::Vector{SVector{P,T}}
	B::SMatrix{P,NM,T,PNM}
	function VariableBoundConstraint(n::Int,m::Int,
			z_max::Vector{<:SVector{NM,T}}, z_min::Vector{<:SVector{NM,T}},
			b::Vector{<:SVector{P}}, B::SMatrix{P,NM,T,PNM}) where {T,P,PN,NM,PNM}
		new{T,P,NM,PNM}(n,m,z_max,z_min,b,B)
	end
end

state_dim(con::VariableBoundConstraint) = con.n
control_dim(con::VariableBoundConstraint) = con.m
is_bound(::VariableBoundConstraint) = true

function evaluate!(vals::Vector{<:AbstractVector},
		con::VariableBoundConstraint, Z::Traj, inds=1:length(Z)-1)
	for (i,k) in enumerate(inds)
		vals[i] = con.B*Z[k].z + con.b[k]
	end
end

function jacobian(con::VariableBoundConstraint, z::KnotPoint)
	return con.B
end

function VariableBoundConstraint(n, m, N;
		x_max=[Inf*(@SVector ones(n)) for k = 1:N], x_min=[-Inf*(@SVector ones(n)) for k = 1:N],
		u_max=[Inf*(@SVector ones(m)) for k = 1:N], u_min=[-Inf*(@SVector ones(m)) for k = 1:N])
	@assert length(x_max) == N
	@assert length(u_max) == N
	@assert length(x_min) == N
	@assert length(u_min) == N

	# Check and convert bounds
	for k = 1:N
		x_max[k], x_min[k] = checkBounds(Val(n), x_max[k], x_min[k])
		u_max[k], u_min[k] = checkBounds(Val(m), u_max[k], u_min[k])
	end

	# Concatenate bounds
	z_max = [SVector{n+m}([x_max[k]; u_max[k]]) for k = 1:N]
	z_min = [SVector{n+m}([x_min[k]; u_min[k]]) for k = 1:N]
	b = [[-z_max[k]; z_min[k]] for k = 1:N]

	active = map(x->isfinite.(x), b)
	equal_active = all(1:N-2) do k
		active[k] == active[k+1]
	end
	if !equal_active
		throw(ArgumentError("All bounds must have the same active constraints"))
	end
	active = active[1]
	p = sum(active)

	inds = SVector{p}(findall(active))

	b = [bi[inds] for bi in b]
	B = SMatrix{2(n+m), n+m}([1.0I(n+m); -1.0I(n+m)])

	VariableBoundConstraint(n, m, z_max, z_min, b, B[inds,:])
end



############################################################################################
#  								INDEXED CONSTRAINT 	 									   #
############################################################################################
""" $(TYPEDEF) Compute a constraint on an arbitrary portion of either the state or control,
or both. Useful for dynamics augmentation. e.g. you are controlling two models, and have
individual constraints on each. You can define constraints as if they applied to the individual
model, and then wrap it in an `IndexedConstraint` to apply it to the appropriate portion of
the concatenated state. Assumes the indexed state portion is contiguous.

Type params:
* S - Inequality or Equality
* W - ConstraintType
* P - Constraint length
* N,M - original state and control dimensions
* NM - N+M
* Bx - location of the first element in the state index
* Bu - location of the first element in the control index
* C - type of original constraint

Constructors:
```julia
IndexedConstraint(n, m, con)
IndexedConstraint(n, m, con, ix::SVector, iu::SVector)
```
where the arguments `n` and `m` are the state and control dimensions of the new dynamics.
`ix` and `iu` are the indices into the state and control vectors. If left out, they are
assumed to start at the beginning of the vector.

NOTE: Only part of this functionality has been tested. Use with caution!
"""
struct IndexedConstraint{S,W,P,N,M,w,C} <: AbstractConstraint{S,W,P}
	n::Int  # new dimension
	m::Int  # new dimension
	con::C
	ix::SVector{N,Int}
	iu::SVector{M,Int}
	∇c::SizedMatrix{P,w,Float64,2}
	A::SubArray{Float64,2,SizedMatrix{P,w,Float64,2},Tuple{UnitRange{Int},UnitRange{Int}},false}
	B::SubArray{Float64,2,SizedMatrix{P,w,Float64,2},Tuple{UnitRange{Int},UnitRange{Int}},false}
end

state_dim(con::IndexedConstraint{<:Any,<:Union{Stage,State}}) = con.n
control_dim(con::IndexedConstraint{<:Any,<:Union{Stage,Control}}) = con.m
Base.length(::IndexedConstraint{S,W,P}) where {S,W,P} = P

function IndexedConstraint(n,m,con::AbstractConstraint{S,W,P},
		ix::SVector{N}, iu::SVector{M}) where {S,W,P,N,M}
	x = @SVector rand(N)
	u = @SVector rand(M)
	w = width(con)
	∇c = SizedMatrix{P,w}(zeros(P,w))
	if W == Stage
		A = view(∇c, 1:P, 1:N)
		B = view(∇c, 1:P, N .+ (1:M))
	else
		A = view(∇c, 1:0, 1:0)
		B = view(∇c, 1:0, 1:0)
	end
	IndexedConstraint{S,W,P,N,M,w,typeof(con)}(n,m,con,ix,iu,∇c,A,B)
end

function IndexedConstraint(n,m,con::AbstractConstraint{S,W}) where {S,W}
	if W <: Union{State,CoupledState}
		m0 = m
	else
		m0 = control_dim(con)
	end
	if W<: Union{Control,CoupledControl}
		n0 = n
	else
		n0 = state_dim(con)
	end
	ix = SVector{n0}(1:n0)
	iu = SVector{m0}(1:m0)
	IndexedConstraint(n,m,con, ix, iu)
end

# TODO: define higher-level evaluate! function instead
@generated function evaluate(con::IndexedConstraint{<:Any,<:Stage,<:Any,N,M}, z::KnotPoint) where {N,M}
	ix = SVector{N}(1:N)
	iu = N .+ SVector{M}(1:M)
	return quote
		x0 = state(z)[con.ix]
		u0 = control(z)[con.iu]
		z_ = StaticKnotPoint([x0; u0], $ix, $iu, z.dt, z.t)
		evaluate(con.con, z_)
	end
end

# TODO: define higher-leel jacobian! function instead
@generated function jacobian!(∇c, con::IndexedConstraint{<:Any,Stage,P,N0,M0},
		z::KnotPoint{<:Any,N}) where {P,N0,M0,N}
	iP = 1:P
	ix = SVector{N0}(1:N0)
	iu = SVector{M0}(N0 .+ (1:M0))
	if eltype(∇c) <: SizedMatrix
		assignment = quote
			uview(∇c.data,$iP,iA) .= con.A
			uview(∇c.data,$iP,iB) .= con.B
		end
	else
		assignment = quote
			uview(∇c,$iP,iA) .= con.A
			uview(∇c,$iP,iB) .= con.B
		end
	end
	quote
		x0 = state(z)[con.ix]
		u0 = control(z)[con.iu]
		z_ = StaticKnotPoint([x0;u0], $ix, $iu, z.dt, z.t)
		jacobian!(con.∇c, con.con, z_)
		iA = con.ix
		iB = N .+ con.iu
		$assignment
	end
end

@generated function jacobian!(∇c, con::IndexedConstraint{<:Any,State,P,N0,M0},
		z::KnotPoint{<:Any,N}) where {P,N0,M0,N}
	iP = 1:P
	ix = SVector{N0}(1:N0)
	iu = SVector{M0}(N0 .+ (1:M0))
	if eltype(∇c) <: SizedArray
		assignment = :(uview(∇c.data,$iP,iA) .= con.∇c)
	else
		assignment = :(uview(∇c,$iP,iA) .= con.∇c)
	end
	quote
		x0 = state(z)[con.ix]
		u0 = control(z)[con.iu]
		z_ = StaticKnotPoint([x0;u0], $ix, $iu, z.dt, z.t)
		jacobian!(con.∇c, con.con, z_)
		iA = con.ix
		$assignment
	end
end

@generated function jacobian!(∇c, con::IndexedConstraint{<:Any,Control,P,N0,M0},
		z::KnotPoint{<:Any,N}) where {P,N0,M0,N}
	iP = 1:P
	ix = SVector{N0}(1:N0)
	iu = SVector{M0}(N0 .+ (1:M0))
	if eltype(∇c) <: SizedArray
		assignment = :(uview(∇c.data,$iP,iB) .= con.∇c)
	else
		assignment = :(uview(∇c,$iP,iB) .= con.∇c)
	end
	quote
		x0 = state(z)[con.ix]
		u0 = control(z)[con.iu]
		z_ = StaticKnotPoint([x0;u0], $ix, $iu, z.dt, z.t)
		jacobian!(con.∇c, con.con, z_)
		iB = con.iu
		$assignment
	end
end
