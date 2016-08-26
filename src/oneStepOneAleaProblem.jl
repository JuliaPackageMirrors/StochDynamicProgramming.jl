#  Copyright 2014, Vincent Leclere, Francois Pacaud and Henri Gerard
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
# Model and solve the One-Step One Alea problem in different settings
# - used to compute the optimal control (in forward phase / simulation)
# - used to compute the cuts in the Backward phase
#############################################################################

"""
Solve the Bellman equation at time t starting at state x under alea xi
with the current evaluation of Vt+1

# Description
The function solve
min_u current_cost(t,x,u,xi) + current_Bellman_Value_{t+1}(dynamic(t,x,u,xi))
and can return the optimal control and a subgradient of the value of the
problem with respect to the initial state x

# Arguments
* `model::SPmodel`:
    the stochastic problem we want to optimize
* `param::SDDPparameters`:
    the parameters of the SDDP algorithm
* `m::JuMP.Model`:
    The linear problem to solve, in order to approximate the
    current value functions
* `t::int`:
    time step at which the problem is solved
* `xt::Array{Float}`:
    current starting state
* `xi::Array{float}`:
    current noise value
* `init::Bool`:
    If specified, approximate future cost as 0

# Returns
* `Bool`:
    True if the solution is feasible, false otherwise
* `NextStep`:
    Store solution of the problem
"""
function solve_one_step_one_alea(model,
                                 param,
                                 m::JuMP.Model,
                                 t::Int64,
                                 xt::Vector{Float64},
                                 xi::Vector{Float64},
                                 init=false::Bool)
    # Get var defined in JuMP.model:
    u = getvariable(m, :u)
    x = getvariable(m, :x)
    alpha = getvariable(m, :alpha)

    # Update value of w:
    JuMP.setRHS(m.ext[:dyn][xi][1][1], m.ext[:dyn][xi][2])
    JuMP.setRHS(m.ext[:dyn][xi][1][2], m.ext[:dyn][xi][2])

    if model.equalityConstraints != nothing
        JuMP.setRHS(m.ext[:eqcons][xi][1], 0)
        JuMP.setRHS(m.ext[:eqcons][xi][2], 0)
    end
    if model.inequalityConstraints != nothing
        JuMP.setRHS(m.ext[:ineqcons][xi], 0)
    end

    # Update constraint x == xt
    for i in 1:model.dimStates
        JuMP.setRHS(m.ext[:cons][i], xt[i])
    end

    if typeof(model) == LinearDynamicLinearCostSPmodel
        @objective(m, Min, model.costFunctions(t, x, u, xi) + alpha)

    elseif typeof(model) == PiecewiseLinearCostSPmodel
        println("not implemented")
    end

    status = solve(m)
    solved = (status == :Optimal)

    if solved
        optimalControl = getvalue(u)
        # Return object storing results:
        result = NextStep(
                          model.dynamics(t, xt, optimalControl, xi),
                          optimalControl,
                          [getdual(m.ext[:cons][i]) for i in 1:model.dimStates],
                          getobjectivevalue(m),
                          getvalue(alpha))
    else
        # If no solution is found, then return nothing
        println(m)
        sleep(100000)
        result = nothing
    end

    JuMP.setRHS(m.ext[:dyn][xi][1][1], our_infinity)
    JuMP.setRHS(m.ext[:dyn][xi][1][2], -our_infinity)

    if model.equalityConstraints != nothing
        JuMP.setRHS(m.ext[:eqcons][xi][1], Inf)
        JuMP.setRHS(m.ext[:eqcons][xi][2], -Inf)
    end
    if model.inequalityConstraints != nothing
        JuMP.setRHS(m.ext[:ineqcons][xi], Inf)
    end

    return solved, result
end

