@doc """`care(A, B, Q, R)`

Compute 'X', the solution to the continuous-time algebraic Riccati equation,
defined as A'X + XA - (XB)R^-1(B'X) + Q = 0, where R is non-singular.

Algorithm taken from:
Laub, "A Schur Method for Solving Algebraic Riccati Equations."
http://dspace.mit.edu/bitstream/handle/1721.1/1301/R-0859-05666488.pdf
""" ->
function care(A, B, Q, R)
    G = try
        B*inv(R)*B'
    catch
        error("R must be non-singular.")
    end

    Z = [A  -G;
        -Q  -A']

    S = schurfact(Z)
    S = ordschur(S, real(S.values).<0)
    U = S.Z

    (m, n) = size(U)
    U11 = U[1:div(m, 2), 1:div(n,2)]
    U21 = U[div(m,2)+1:m, 1:div(n,2)]
    return U21/U11
end

@doc """`dare(A, B, Q, R)`

Compute `X`, the solution to the discrete-time algebraic Riccati equation,
defined as A'XA - X - (A'XB)(B'XB + R)^-1(B'XA) + Q = 0, where A and R
are non-singular.

Algorithm taken from:
Laub, "A Schur Method for Solving Algebraic Riccati Equations."
http://dspace.mit.edu/bitstream/handle/1721.1/1301/R-0859-05666488.pdf
""" ->
function dare(A, B, Q, R)
    G = try
        B*inv(R)*B'
    catch
        error("R must be non-singular.")
    end

    Ait = try
        inv(A)'
    catch
        error("A must be non-singular.")
    end

    Z = [A + G*Ait*Q   -G*Ait;
         -Ait*Q        Ait]

    S = schurfact(Z)
    S = ordschur(S, abs(S.values).<=1)
    U = S.Z

    (m, n) = size(U)
    U11 = U[1:div(m, 2), 1:div(n,2)]
    U21 = U[div(m,2)+1:m, 1:div(n,2)]
    return U21/U11
end

@doc """`dlyap(A, Q)`

Compute the solution "X" to the discrete Lyapunov equation
"AXA' - X + Q = 0".
""" ->
function dlyap(A, Q)
    lhs = kron(A, conj(A))
    lhs = eye(size(lhs, 1)) - lhs
    x = lhs\reshape(Q, prod(size(Q)), 1)
    return reshape(x, size(Q))
end

@doc """`gram(sys, opt)`

Compute the grammian of system `sys`. If `opt` is `:c`, computes the
controllability grammian. If `opt` is `:o`, computes the observability
grammian.""" ->
function gram(sys::StateSpace, opt::Symbol)
    if !isstable(sys)
        error("gram only valid for stable A")
    end
    func = iscontinuous(sys) ? lyap : dlyap
    if opt == :c
        return func(sys.A, sys.B*sys.B')
    elseif opt == :o
        return func(sys.A', sys.C'*sys.C)
    else
        error("opt must be either :c for controllability grammian, or :o for
                observability grammian")
    end
end

@doc """`obsv(A, C)` or `obsv(sys)`

Compute the observability matrix for the system described by `(A, C)` or `sys`.

Note that checking for observability by computing the rank from `obsv` is
not the most numerically accurate way, a better method is checking if
`gram(sys, :o)` is positive definite.""" ->
function obsv(A, C)
    n = size(A, 1)
    ny = size(C, 1)
    if n != size(C, 2)
        error("C must have the same number of columns as A")
    end
    res = zeros(n*ny, n)
    res[1:ny, :] = C
    for i=1:n-1
        res[(1 + i*ny):(1 + i)*ny, :] = res[((i - 1)*ny + 1):i*ny, :] * A
    end
    return res
end
obsv(sys::StateSpace) = obsv(sys.A, sys.C)

@doc """`ctrb(A, B)` or `ctrb(sys)`

Compute the controllability matrix for the system described by `(A, B)` or
`sys`.

Note that checking for controllability by computing the rank from
`obsv` is not the most numerically accurate way, a better method is
checking if `gram(sys, :c)` is positive definite.""" ->
function ctrb(A, B)
    n = size(A, 1)
    nu = size(B, 2)
    if n != size(B, 1)
        error("B must have the same number of rows as A")
    end
    res = zeros(n, n*nu)
    res[:, 1:nu] = B
    for i=1:n-1
        res[:, (1 + i*nu):(1 + i)*nu] = A * res[:, ((i - 1)*nu + 1):i*nu]
    end
    return res
end
ctrb(sys::StateSpace) = ctrb(sys.A, sys.B)

@doc """`P = covar(sys, W)`

Calculate the stationary covariance `P = E[y(t)y(t)']` of an lti-model `sys`, driven by gaussian
white noise 'w' of covariance `E[w(t)w(τ)]=W*δ(t-τ)` where δ is the dirac delta.

The ouput is if Inf if the system is unstable. Passing white noise directly to
the output will result in infinite covariance in the corresponding outputs
(D*W*D.' .!= 0) for contunuous systems.""" ->
function covar(sys::StateSpace, W::StridedMatrix)
    (A, B, C, D) = (sys.A, sys.B, sys.C, sys.D)
    if size(B,2) != size(W, 1) || size(W, 1) != size(W, 2)
        error("W must be a square matrix the same size as `sys.B` columns")
    end
    if !isstable(sys)
        return fill(Inf,(size(C,1),size(C,1)))
    end
    func = iscontinuous(sys) ? lyap : dlyap
    Q = try
        func(A, B*W*B')
    catch
        error("No solution to the Lyapunov equation was found in covar")
    end
    P = C*Q*C'
    if iscontinuous(sys)
        #Variance and covariance infinite for direct terms
        directNoise = D*W*D'
        for i in 1:size(C,1)
            if directNoise[i,i] != 0
                P[i,:] = Inf
                P[:,i] = Inf
            end
        end
    else
        P += D*W*D'
    end
    return P
end

covar(sys::TransferFunction, W::StridedMatrix) = covar(ss(sys), W)


# Note: the H∞ norm computation is probably not as accurate as with SLICOT, 
# but this seems to be still reasonably ok as a first step
@doc """
`..  norm(sys, p=2; tol=1e-6)`

`norm(sys)` or `norm(sys,2)` computes the H2 norm of the LTI system `sys`.

`norm(sys, Inf)` computes the L∞ norm of the LTI system `sys`. 
The H∞ norm is the same as the L∞ for stable systems, and Inf for unstable systems.
If the peak gain frequency is required as well, use the function `norminf` instead.

`tol` is an optional keyword argument, used only for the computation of L∞ norms.
It represents the desired relative accuracy for the computed L∞ norm
(this is not an absolute certificate however).

sys is first converted to a state space model if needed.

The L∞ norm computation implements the 'two-step algorithm' in:
N.A. Bruinsma and M. Steinbuch, 'A fast algorithm to compute the H∞-norm
of a transfer function matrix', Systems and Control Letters 14 (1990), pp. 287-293.
For the discrete-time version, see, e.g.,: P. Bongers, O. Bosgra, M. Steinbuch, 'L∞-norm
calculation for generalized state space systems in continuous and discrete time', 
American Control Conference, 1991.
""" ->
function Base.norm(sys::StateSpace, p::Real=2; tol=1e-6)
    if p == 2
        return sqrt(trace(covar(sys, eye(size(sys.B, 2)))))
    elseif p == Inf
        if sys.Ts == 0
            return normLinf_twoSteps_ct(sys,tol)[1]
        else
            return normLinf_twoSteps_dt(sys,tol)[1]
        end
    else
        error("`p` must be either `2` or `Inf`")
    end
end

function Base.norm(sys::TransferFunction, p::Real=2; tol=1e-6)
    return Base.norm(ss(sys), p, tol=tol)
end

@doc """
`.. (peakgain, peakgainfrequency) = norminf(sys; tol=1e-6)`

Compute the L∞ norm of the LTI system `sys`, together with the frequency 
`peakgainfrequency` (in rad/TimeUnit) at which the gain achieves its peak value `peakgain`.
The H∞ norm is the same as the L∞ for stable systems, and Inf for unstable systems.

`tol` is an optional keyword argument representing the desired relative accuracy for 
the computed L∞ norm (this is not an absolute certificate however).

sys is first converted to a state space model if needed.

The L∞ norm computation implements the 'two-step algorithm' in:
N.A. Bruinsma and M. Steinbuch, 'A fast algorithm to compute the H∞-norm
of a transfer function matrix', Systems and Control Letters 14 (1990), pp. 287-293.
For the discrete-time version, see, e.g.,: P. Bongers, O. Bosgra, M. Steinbuch, 'L∞-norm
calculation for generalized state space systems in continuous and discrete time', 
American Control Conference, 1991.
""" ->
function norminf(sys::StateSpace; tol=1e-6)
    if sys.Ts == 0
        return normLinf_twoSteps_ct(sys,tol)
    else
        return normLinf_twoSteps_dt(sys,tol)
    end
end

function norminf(sys::TransferFunction, ; tol=1e-6)
    return norminf(ss(sys), tol=tol)
end

function normLinf_twoSteps_ct(sys::StateSpace, tol=1e-6, maxIters=1000, approximag=1e-10)
    # `maxIters`: the maximum  number of iterations allowed in the algorithm (default 1000)
    # approximag is a tuning parameter: what does it mean for a number to be on the imaginary axis
    # Because of this tuning for example, the relative precision that we provide on the norm computation
    # is not a true guarantee, more an order of magnitude
    # outputs: pair of Float64, namely L∞ norm approximation and frequency fpeak at which it is achieved
    if sys.nx == 0  # static gain
        return (norm(sys.D,2), 0.0)
    end
    p = pole(sys)
    # Check if there is a pole on the imaginary axis
    pidx = findfirst(map(x->isapprox(x,0.0),real(p)))
    if pidx > 0
        return (Inf, imag(p[pidx]))
        # note: in case of cancellation, for s/s for example, we return Inf, whereas Matlab returns 1
    else
        # Initialization: computation of a lower bound from 3 terms
        lb = maximum(svdvals(sys.D)); fpeak = Inf
        (lb, idx) = findmax([lb, maximum(svdvals(evalfr(sys,0)))])
        if idx == 2
            fpeak = 0
        end
        if isreal(p)  # only real poles
            omegap = minimum(abs(p))
        else  # at least one pair of complex poles
            tmp = maximum(abs(imag(p)./(real(p).*abs(p))))
            omegap = abs(p[indmax(tmp)])
        end
        (lb, idx) = findmax([lb, maximum(svdvals(evalfr(sys, omegap*1im)))])
        if idx == 2
            fpeak = omegap
        end

        # Iterations
        iter = 1;
        while iter <= maxIters
            res = (1+2tol)*lb
            R = sys.D'*sys.D - res^2*eye(sys.nu)
            S = sys.D*sys.D' - res^2*eye(sys.ny)
            M = sys.A-sys.B*(R\sys.D')*sys.C
            H = [         M              -res*sys.B*(R\sys.B') ;
                   res*sys.C'*(S\sys.C)            -M'            ]
            omegas = eigvals(H)
            omegaps = imag(omegas[ (abs(real(omegas)).<=approximag) & (imag(omegas).>=0) ])
            sort!(omegaps)
            if isempty(omegaps)
                return (1+tol)*lb, fpeak
            else  # if not empty, omegaps contains at least two values
                ms = [(x+y)/2 for x=omegaps[1:end-1], y=omegaps[2:end]]
                for mval in ms
                    (lb, idx) = findmax([lb, maximum(svdvals(evalfr(sys,mval*1im)))])
                    if idx == 2
                        fpeak = mval
                    end
                end
            end
            iter += 1
        end
        println("The computation of the H-infinity norm did not converge in $maxIters iterations")
    end
end

# discrete-time version of normHinf_twoSteps_ct above
# The value fpeak returned by the function is in the range [0,pi)/sys.Ts (in rad/s)
function normLinf_twoSteps_dt(sys::StateSpace,tol=1e-6,maxIters=1000,approxcirc=1e-8)
    if sys.nx == 0  # static gain
        return (norm(sys.D,2), 0.0)
    end
    p = pole(sys)
    # Check first if there is a pole on the unit circle
    pidx = findfirst(map(x->isapprox(x,1.0),abs(p)))
    if (pidx > 0)
        return (Inf, angle(p[pidx])/abs(sys.Ts))
    else
        # Initialization: computation of a lower bound from 3 terms
        lb = maximum(svdvals(evalfr(sys,1))); fpeak = 0
        (lb, idx) = findmax([lb, maximum(svdvals(evalfr(sys,-1)))])
        if idx == 2
            fpeak = pi
        end

        p = p[imag(p).>0]
        if ~isempty(p)  # not just real poles
            # find frequency of pôle closest to unit circle
            omegap = angle(p[findmin(abs(abs(p)-1))[2]])
        else 
            omegap = pi/2
        end
        (lb, idx) = findmax([lb, maximum(svdvals(evalfr(sys, exp(omegap*1im))))])
        if idx == 2
            fpeak = omegap
        end

        # Iterations
        iter = 1;
        while iter <= maxIters
            res = (1+2tol)*lb
            R = res^2*eye(sys.nu) - sys.D'*sys.D
            RinvDt = R\sys.D'
            L = [ sys.A+sys.B*RinvDt*sys.C  sys.B*(R\sys.B');
                  zeros(sys.nx,sys.nx)      eye(sys.nx)]
            M = [ eye(sys.nx)                              zeros(sys.nx,sys.nx); 
                  sys.C'*(eye(sys.ny)+sys.D*RinvDt)*sys.C  L[1:sys.nx,1:sys.nx]']
            zs = eig(L,M)[1]  # generalized eigenvalues
            # are there eigenvalues on the unit circle?
            omegaps = angle(zs[ (abs(abs(zs)-1) .<= approxcirc) & (imag(zs).>=0)])
            sort!(omegaps)
            if isempty(omegaps)
                return (1+tol)*lb, fpeak/sys.Ts
            else  # if not empty, omegaps contains at least two values
                ms = [(x+y)/2 for x=omegaps[1:end-1], y=omegaps[2:end]]
                for mval in ms
                    (lb, idx) = findmax([lb, maximum(svdvals(evalfr(sys,exp(mval*1im))))])
                    if idx == 2
                        fpeak = mval
                    end
                end
            end
            iter += 1
        end
        println("The computation of the H-infinity norm did not converge in $maxIters iterations")
    end
end


@doc """`T, B = balance(A[, perm=true])`

Compute a similarity transform `T` resulting in `B = T\\A*T` such that the row
and column norms of `B` are approximately equivalent. If `perm=false`, the
transformation will only scale, and not permute `A`.""" ->
function balance(A, perm::Bool=true)
    n = Base.LinAlg.checksquare(A)
    B = copy(A)
    job = perm ? 'B' : 'S'
    ilo, ihi, scaling = LAPACK.gebal!(job, B)

    S = diagm(scaling)
    for j = 1:(ilo-1)   S[j,j] = 1 end
    for j = (ihi+1):n   S[j,j] = 1 end

    P = eye(Int, n)
    if perm
        if ilo > 1
            for j = (ilo-1):-1:1 cswap!(j, round(Int, scaling[j]), P) end
        end
        if ihi < n
            for j = (ihi+1):n    cswap!(j, round(Int, scaling[j]), P) end
        end
    end
    return S, P, B
end

function cswap!{T<:Number}(i::Integer, j::Integer, X::StridedMatrix{T})
    for k = 1:size(X,1)
        X[i, k], X[j, k] = X[j, k], X[i, k]
    end
end



"""
`sysr, G = balreal(sys::StateSpace)`

Calculates a balance realization of the system sys, such that the observability and reachability gramians of the balanced system are equal and diagonal `G`

See also `gram`

Glad, Ljung, Reglerteori: Flervariabla och Olinjära metoder
"""
function balreal(sys::StateSpace)
P = gram(sys, :c)
Q = gram(sys, :o)
Q1 = chol(Q)
U,Σ,V = svd(Q1*P*Q1')
Σ = sqrt(Σ)
Σ1 = diagm((sqrt(Σ)))
T = Σ1\(U'Q1)

Pz = T*P*T'
Qz = inv(T')*Q*inv(T)
if vecnorm(Pz-Qz) > sqrt(eps())
    warn("balreal: Result may be inaccurate")
    println("Controllability gramian before transform")
    display(P)
    println("Controllability gramian after transform")
    display(Pz)
    println("Observability gramian before transform")
    display(Q)
    println("Observability gramian after transform")
    display(Qz)
    println("Singular values of PQ")
    display(Σ)
end

sysr = ss(T*sys.A/T, T*sys.B, sys.C/T, sys.D), diagm(Σ)
end
