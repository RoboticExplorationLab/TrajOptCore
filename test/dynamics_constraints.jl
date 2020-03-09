model = RobotZoo.Cartpole()
prob = gen_cartpole_prob()
bnd = TOC.get_constraints(prob).constraints[1]
n,m = size(prob)

N = prob.N
rollout!(prob)
Z = prob.Z
vals = [@SVector zeros(model.n) for k = 1:N-1]

∇c = [SizedMatrix{n,2n+m}(zeros(n,2n+m)) for k = 1:N-1]
dyn_con = DynamicsConstraint{RK3}(model, N)
@test TOC.width(dyn_con) == 2n+m
evaluate!(vals, dyn_con, Z)
jacobian!(∇c, dyn_con, Z)
@test (@allocated evaluate!(vals, dyn_con, Z)) == 0
@test (@allocated jacobian!(∇c, dyn_con, Z)) == 0

con_rk3 = ConstraintVals(dyn_con, 1:N-1)
evaluate!(con_rk3, Z)
jacobian!(con_rk3, Z)
TOC.max_violation!(con_rk3)
maximum(con_rk3.c_max)
@test (@allocated evaluate!(con_rk3, Z)) == 0
@test (@allocated jacobian!(con_rk3, Z)) == 0

∇c = [zeros(SizedMatrix{n,2n+2m}) for k = 1:N-1]
dyn_con = DynamicsConstraint{HermiteSimpson}(model, N)
@test TOC.width(dyn_con) == 2(n+m)
evaluate!(vals, dyn_con, Z)
jacobian!(∇c, dyn_con, Z)
@test (@allocated evaluate!(vals, dyn_con, Z)) == 0
@test (@allocated jacobian!(∇c, dyn_con, Z)) == 0

con_hs = ConstraintVals(dyn_con, 1:N-1)
evaluate!(con_hs, Z)
jacobian!(con_hs, Z)
@test (@allocated evaluate!(con_hs, Z)) == 0
@test (@allocated jacobian!(con_hs, Z)) == 0


# Test default
dyn_con = DynamicsConstraint(model, N)
@test integration(dyn_con) == RK3 == TOC.DEFAULT_Q
