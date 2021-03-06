#  Copyright 2015, Vincent Leclere, Francois Pacaud and Henri Gerard
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
# Test SDDP with dam example
# Source: Adrien Cassegrain
#############################################################################

#srand(2713)

using StochDynamicProgramming, JuMP, Clp

#Constant that the user have to define himself
const SOLVER = ClpSolver()
# const SOLVER = CplexSolver(CPX_PARAM_SIMDISPLAY=0)

const N_STAGES = 3
const N_SCENARIOS = 2

const DIM_STATES = 1
const DIM_CONTROLS = 2
const DIM_ALEAS = 1



#Constants that the user does not have to define
const T0 = 1

const CONTROL_MAX = round(Int, .4/7. * 100) + 1
const CONTROL_MIN = 0

const W_MAX = round(Int, .5/7. * 100)
const W_MIN = 0
const DW = 1

# Define aleas' space:
const N_ALEAS = Int(round(Int, (W_MAX - W_MIN) / DW + 1))
const ALEAS = linspace(W_MIN, W_MAX, N_ALEAS)

const EPSILON = .05
const MAX_ITER = 20

const X0 = 50*ones(DIM_STATES)

Ax=[]
Au=[]
Aw=[]

Cx=[]
Cu=[]
Cw=[]

function generate_random_dynamic()
    for i=1:N_STAGES
        push!(Ax, rand(DIM_STATES,DIM_STATES))
        push!(Au, rand(DIM_STATES,DIM_CONTROLS))
        push!(Aw, rand(DIM_STATES,DIM_ALEAS))
    end
end

function generate_random_costs()
    for i=1:N_STAGES
        push!(Cx, rand(1,DIM_STATES))
        push!(Cu, -1*rand(1,DIM_CONTROLS))
        push!(Cw, rand(1,DIM_ALEAS))
    end
end

generate_random_dynamic()
generate_random_costs()

# Define dynamic of the dam:
function dynamic(t, x, u, w)
    return  Ax[t]*x+Au[t]*u+Aw[t]*w
end

# Define cost corresponding to each timestep:
function cost_t(t, x, u, w)
    return (Cx[t]*x)[1,1]+(Cu[t]*u)[1,1]+(Cw[t]*w)[1,1]
end


"""Build aleas probabilities for each month."""
function build_aleas()
    aleas = zeros(N_ALEAS, N_STAGES)

    # take into account seasonality effects:
    unorm_prob = linspace(1, N_ALEAS, N_ALEAS)
    proba1 = unorm_prob / sum(unorm_prob)
    proba2 = proba1[N_ALEAS:-1:1]

    for t in 1:N_STAGES
        aleas[:, t] = (1 - sin(pi*t/N_STAGES)) * proba1 + sin(pi*t/N_STAGES) * proba2
    end
    return aleas
end


"""Build an admissible scenario for water inflow."""
function build_scenarios(n_scenarios::Int64, probabilities)
    scenarios = zeros(n_scenarios, N_STAGES)

    for scen in 1:n_scenarios
        for t in 1:N_STAGES
            Pcum = cumsum(probabilities[:, t])

            n_random = rand()
            prob = findfirst(x -> x > n_random, Pcum)
            scenarios[scen, t] = prob
        end
    end
    return scenarios
end


"""Build probability distribution at each timestep.

Return a Vector{NoiseLaw}"""
function generate_probability_laws()
    aleas = build_scenarios(N_SCENARIOS, build_aleas())

    laws = Vector{NoiseLaw}(N_STAGES)

    # uniform probabilities:
    proba = 1/N_SCENARIOS*ones(N_SCENARIOS)

    for t=1:N_STAGES
        laws[t] = NoiseLaw(aleas[:, t], proba)
    end

    return laws
end


"""Instantiate the problem."""
function init_problem()

    x0 = X0
    aleas = generate_probability_laws()

    #Define bounds for the control
    u_bounds  = [(CONTROL_MIN, CONTROL_MAX) for i in 1:DIM_CONTROLS]

    model = LinearDynamicLinearCostSPmodel(N_STAGES,
                                                u_bounds,
                                                x0,
                                                cost_t,
                                                dynamic,
                                                aleas)

    params = SDDPparameters(SOLVER, N_SCENARIOS, EPSILON, MAX_ITER)

    return model, params
end

model, params = init_problem()
modelbis = deepcopy(model)
paramsbis = deepcopy(params)


"""Solve the problem."""
function solve_dams(model,params,display=false)

    V, pbs = solve_SDDP(model, params, display)

    aleas = simulate_scenarios(model.noises,params.forwardPassNumber)

    params.forwardPassNumber = 1

    costs, stocks = forward_simulations(model, params, pbs, aleas)
    println("SDDP cost: ", costs)
    return stocks, V
end

#Solve the problem and try nb_iter times to generate random data in case of infeasibility
unsolve = true
sol = 0
firstControl = zeros(DIM_CONTROLS*N_SCENARIOS)
i = 0
nb_iter = 10

while i<nb_iter
    sol, firstControl, status = extensive_formulation(model,params)
    if (status == :Optimal)
        unsolve = false
        break
    else
        println("\nGenerate new dynamic to reach feasability\n")
        Ax=[]
        Au=[]
        Aw=[]
        generate_random_dynamic()
        model, params = init_problem()
        modelbis = model
        paramsbis = params
        i = i+1
    end
end


if (unsolve)
    println("Change your parameters")
else
    a,b = solve_dams(modelbis,paramsbis)
    println("solution =",sol)
    println("firstControl =", firstControl)
    println("V0 = ", b[1].lambdas[1,:]*X0+b[1].betas[1])
end

