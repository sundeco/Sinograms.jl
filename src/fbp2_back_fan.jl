# fbp2_back_fan.jl
# obsolete: fbp2_back now covers both fan and par case

export fbp2_back_fan


using LazyGrids: ndgrid

"""
    img = fbp2_back_fan(sg, ig, sino; ia_skip)

2D backprojection for fan-beam FBP.

in
- `sg::SinoGeom`
- `ig::ImageGeom`
- `sino::AbstractArray{<:Number}`      sinogram(s) (line integrals)

options
- `ia_skip::Int`                        downsample in angle to save time for quick tests (default: 1)

out
- `img::AbstractArray{<:Number}`       reconstructed image(s)

"""
function fbp2_back_fan(sg::SinoGeom, ig::ImageGeom, sino::AbstractMatrix{<:Number}; ia_skip::Int=1)

    sg isa SinoFan || throw("need fan type")

    if sg.dfs == 0
        is_arc=true
    elseif isinf(dsf)
        is_arc=false
    else
        throw("bad dsf")
    end

    return fbp2_back_fan(sino, sg.orbit, sg.orbit_start,
    sg.dsd, sg.dso, sg.dfs, sg.ds, sg.offset,
    sg.source_offset,
    ig.nx, ig.ny, ig.dx, ig.dy, ig.offset_x, ig.offset_y,
    is_arc, ig.mask, ia_skip)

end

function fbp2_back_fan(sino::AbstractMatrix{<:Number}, orbit::Union{Symbol,Real}, orbit_start::Real,
    dsd::RealU, dso::Real, dfs::RealU, ds::RealU, offset::Real, source_offset::Real,
    nx::Int, ny::Int, dx::RealU, dy::RealU, offset_x::Real, offset_y::Real,
     is_arc::Bool, mask::AbstractMatrix{Bool}, ia_skip::Int,
)
    rmax=[]

    na,nb=size(sino)

    # trick: extra zero column saves linear interpolation indexing within loop!
    sino = [sino;zeros(eltype(sino),size(sino,2),2)']

    # precompute as much as possible
    wx = (nx+1)/2 - offset_x
    wy = (ny+1)/2 - offset_y
    xc, yc = ndgrid(dx * ((1:nx) .- wx), dy * ((1:ny) .- wy))
    rr = @.(sqrt(abs2(xc) + abs2(yc))) # [nx,ny]

    smax = ((nb-1)/2 - abs(offset)) * ds

    #todo: rmax possibly extracable from SinoGeom
    if is_arc
        gamma_max = smax / dsd
    else # flat
        gamma_max = atan(smax / dsd)
    end
    rmax = dso * sin(gamma_max)

    mask = mask .& (rr .< rmax)
    xc = xc[vec(mask)] # [np] pixels within mask
    yc = yc[vec(mask)]
    #clear wx wy rr smax

    betas = @.(deg2rad(orbit_start + orbit * (0:na-1) / na)) # [na]
    wb = (nb+1)/2 + offset

    img = 0

    for ia=1:ia_skip:na
    #ticker(mfilename, ia, na)

        beta = betas[ia]
        d_loop = @.(dso + xc * sin(beta) - yc * cos(beta)) # dso - y_beta
        r_loop = @.(xc * cos(beta) + yc * sin(beta) - source_offset) # x_beta-roff

        if is_arc
            sprime_ds = (dsd/ds) * atan.(r_loop, d_loop) # s' / ds
            w2 = @.(dsd^2 / (abs2(d_loop) + abs2(r_loop))) # [np] image weighting
        else # flat
            mag = dsd ./ d_loop
            sprime_ds = mag .* r_loop ./ ds
            w2 = abs2.(mag) # [np] image-domain weighting
        end

        bb = sprime_ds .+ wb # [np] bin "index"

        # nearest neighbor interpolation:
        #=
    %    ib = round(bb);
    %    if any(ib < 1 | ib > nb), error 'bug', end
    %    % trick: make out-of-sinogram indices point to those extra zeros
    %%    ib(ib < 1 | ib > nb) = nb+1;
    %    img = img + sino(ib, ia) ./ L2;
        =#

        # linear interpolation:
        il = floor.(Int, bb) # left bin
        ir = 1 .+ il # right bin

        # deal with truncated sinograms
        ig = (il .>= 1) .& (ir .<= nb)
        il[.!ig] .= nb+1
        ir[.!ig] .= nb+1
    #    if any(il < 1 | il >= nb), error 'bug', end

    # Temporary:
        il=min.(il,na)
        ir=min.(ir,na)

        wr = bb .- il # left weight
        wl = 1 .- wr # right weight

        img = @.(img + (wl * sino[il, ia] + wr * sino[ir, ia]) * w2)
    end

    return π / (na/ia_skip) * embed(img,mask)
end


function fbp2_back_fan(sg::SinoGeom, ig::ImageGeom, sino::AbstractArray{<:Number}; kwargs...)
    return mapslices(sino -> fbp2_back_fan(sg, ig, sino; kwargs...), sino, [1,2])
end

