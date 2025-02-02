function t_imag(t1::NTuple{N,T}) where {N,T}
    imag.(t1)
end

function t_sum(t1::NTuple{N,T}, t2::NTuple{N,T}) where {N,T}
    t1 .+ t2
end

function sum_t(ts::AbstractArray{T,D}) where {T,D}
    reduce(t_sum, ts)
end

"""
    sum_res_i(dat::Array{T,D}, pvec::Array{T2,1}) where {T,T2,D}
    a helper function for the gradient of a sum over an exponential
"""
function sum_res_i(dat::Array{T,D}, pvec::Array{T2,1}) where {T,T2,D}
    sz = size(dat)
    mymid = (sz.÷2).+1
    f = (p, sz, pvec) -> cis(pvec * p)
    # s1 = sum(conj.(dat) .* separable_view(f, sz, pvec))
    f_sep = calculate_separables(Array{T,D}, f, sz, pvec)
    s1 = sum(conj.(dat) .* (f_sep...))

    times_pos(p,d) = (p .-mymid) .* d
    g = (p, sz, pvec) -> cis(- pvec * p)
    # s2 = sum_t(apply_tuple_list.(times_pos, Tuple.(CartesianIndices(sz)), dat .* separable_view(g, sz, pvec)))
    f_sep2 = calculate_separables(Array{T,D}, g, sz, pvec)
    s2 = sum_t(apply_tuple_list.(times_pos, Tuple.(CartesianIndices(sz)), dat .* (f_sep2...)))
    imag.(s1 .* s2)  # t_imag
end

function find_max(dat; exclude_zero=true)
    arr = abs.(dat)
    mid = center(size(arr), CenterFT)
    if exclude_zero
        arr[mid...] = 0
    end
    arr[mid...] 
    m,p = findmax(arr)
    Tuple(p) .- mid
end

""" 
    arg_n(n,args...)
    returns a Tuple of the n^th vector in args

# Example
```julia
```
"""
function arg_n(n,args)
    return (a[n] for a in args)
end

# """
#     separable_view{N}(fct, sz, args...)

# creates an array view of an N-dimensional separable function.
# Note that this view consumes much less memory than a full allocation of the collected result.
# Note also that an N-dimensional calculation expression may be much slower than this view reprentation of a product of N one-dimensional arrays.
# See the example below.
    
# # Arguments:
# + fct: The separable function, with a number of arguments corresponding to `length(args)`, each corresponding to a vector of separable inputs of length N.
#         The first argument of this function is a Tuple corresponding the centered indices.
# + sz: The size of the N-dimensional array to create
# + args...: a list of arguments, each being an N-dimensional vector

# # Example:
# ```julia
# julia> pos = (0.1, 0.2); sigma = (0.5, 1.0);
# julia> fct = (r, pos, sigma)-> exp(-(r-pos)^2/(2*sigma^2))

# julia> my_gaussian = separable_view(fct, (6,5), (0.1,0.2),(0.5,1.0))
# (6-element Vector{Float64}) .* (1×5 Matrix{Float64}):
#  3.99823e-10  2.18861e-9   4.40732e-9   3.26502e-9   8.89822e-10
#  1.3138e-5    7.19168e-5   0.000144823  0.000107287  2.92392e-5
#  0.00790705   0.0432828    0.0871609    0.0645703    0.0175975
#  0.0871609    0.477114     0.960789     0.71177      0.19398
#  0.0175975    0.0963276    0.19398      0.143704     0.0391639
#  6.50731e-5   0.000356206  0.000717312  0.000531398  0.000144823
# ```
# """
# function separable_view(fct, sz::NTuple{N, Int}, args...) where {N}
#     first_args = arg_n(1, args)
#     start = -sz[1].÷2 
#     idc = start:start+sz[1]-1
#     res = [] # Vector{Array{Float64}}()
#     push!(res, collect(fct.(idc, first_args...)))
#     for d = 2:N
#         start = -sz[d].÷2 
#         idc = start:start+sz[d]-1
#         # myaxis = collect(fct.(idc,arg_n(d, args)...)) # no need to reorient
#         myaxis = collect(reorient(fct.(idc,arg_n(d, args)...), d, Val(N)))
#         # LazyArray representation of expression
#         push!(res, myaxis)
#     end
#     LazyArray(@~ .*(res...)) # multiply them all together
# end

function t_arr_prod(arr::Vector{Vector{T}}, c::CartesianIndex{N})::T where {T,N, TI}
    res = arr[1][c[1]]
    for d in 2:N
        res *= arr[d][c[d]]
    end
    return res
    # prod((arr[d][c[d]] for d in 1:N))
end

# hf enhancement for better visualization and peak finding
function beautify(x)
    rr2(size(x)).*sum(abs.(x),dims=3)
end

function even_size(sz)
    sz.÷2 .*2
end

# using FourierTools, TestImages, NDTools, View5D, IndexFunArrays
#using SubpixelRegistration
function make_even(img)
    select_region(img, new_size=even_size(size(img)))
end

function replace_nan(v::AbstractArray{T,N}) where {T,N}
    map(x -> isnan(x) ? zero(T) : x, v)
end

"""
    extract_patches(img, markers=nothing, patch_size=max.(size(img) .÷5,5))
    extracts pathes, usually near at the corners as defined by the patch center positions
    `markers`. The patch size can be specified by `patch_size`.
#Arguments
+ img:          image from which the patches are extracted using `select_region` from the NDTools package.
+ markers:      a vector of center positions where the alignment should be determined. If `nothing` is provided, positions at 25% and 75% of each coordinates are chosen.
+ patch_size:   tuple denoting the size of each patch

"""
function extract_patches(img, markers=nothing; grid_size=(5,5), patch_size=max.(size(img) .÷ 5,5), avoid_border=true)
    patches = []
    markers = let
        if isnothing(markers)
            nodes = get_default_markers(img, grid_size)
            # omit the borders markers
            if avoid_border
                mar = [floor.(Int,(nodes[1][n], nodes[2][m])) for m = 2:grid_size[2]-1 for n = 2:grid_size[1]-1]
            else
                mar = []
                for m = 1:grid_size[2] 
                    for n = 1:grid_size[1]
                        m1 = (nodes[1][n], nodes[2][m])
                        m2 = (nodes[1][clamp(n,1,grid_size[1]-1)], nodes[2][clamp(m,1,grid_size[2]-1)])
                        push!(mar,floor.(Int,(m1 .+ m2)./2))
                    end
                end
                # mar = [floor.(Int,(nodes[1][n], nodes[2][m])) for m = 1:grid_size[2] for n = 1:grid_size[1]]
                mar
            end

            # the line above leads to deformantions. This can be fixed.
        else
            markers
        end
    end
    for m in markers
        patch = select_region(img, new_size=patch_size, center=Tuple(m))
        push!(patches, patch)
    end
    return patches, markers # cat(patches..., dims=ndims(img)+1)
end

function band_pass(img, s, e) 
    gaussf(img,s) .- gaussf(img,e)
end
