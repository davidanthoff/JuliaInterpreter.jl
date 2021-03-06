module JuliaInterpreter

using Base.Meta
import Base: +, -, convert, isless
using Core: CodeInfo, SSAValue, SlotNumber, TypeMapEntry, SimpleVector, LineInfoNode, GotoNode, Slot,
            GeneratedFunctionStub, MethodInstance, NewvarNode, TypeName

using UUIDs
# The following are for circumventing #28, memcpy invalid instruction error,
# in Base and stdlib
using Random.DSFMT
using InteractiveUtils
using CodeTracking

export @interpret, Compiled, Frame, root, leaf,
       BreakpointRef, breakpoint, @breakpoint, breakpoints, enable, disable, remove,
       debug_command, @bp, break_on, break_off

module CompiledCalls
# This module is for handling intrinsics that must be compiled (llvmcall)
end

const BUILTIN_FILE = joinpath(@__DIR__, "builtins-julia$(Int(VERSION.major)).$(Int(VERSION.minor)).jl")

@info "Generating builtins for this julia version..."
gen_builtins_file = joinpath(@__DIR__, "generate_builtins.jl")
# Run as separate command to prevent including the generate_builtins into the precompile cache
run(`$(Base.julia_cmd()) --startup-file=no $gen_builtins_file`)
include_dependency(gen_builtins_file)

include("types.jl")
include("utils.jl")
include("construct.jl")
include("localmethtable.jl")
include("interpret.jl")
include(BUILTIN_FILE)
include("optimize.jl")
include("commands.jl")
include("breakpoints.jl")

function set_compiled_methods()
    # Work around #28 by preventing interpretation of all Base methods that have a ccall to memcpy
    push!(compiled_methods, which(vcat, (Vector,)))
    push!(compiled_methods, first(methods(Base._getindex_ra)))
    push!(compiled_methods, first(methods(Base._setindex_ra!)))
    push!(compiled_methods, which(Base.decompose, (BigFloat,)))
    push!(compiled_methods, which(DSFMT.dsfmt_jump, (DSFMT.DSFMT_state, DSFMT.GF2X)))
    if Sys.iswindows()
        push!(compiled_methods, which(InteractiveUtils.clipboard, (AbstractString,)))
    end
    # issue #76
    push!(compiled_methods, which(unsafe_store!, (Ptr{Any}, Any, Int)))
    push!(compiled_methods, which(unsafe_store!, (Ptr, Any, Int)))
    # issue #92
    push!(compiled_methods, which(objectid, Tuple{Any}))
    # issue #106 --- anything that uses sigatomic_(begin|end)
    push!(compiled_methods, which(flush, Tuple{IOStream}))
    push!(compiled_methods, which(disable_sigint, Tuple{Function}))
    push!(compiled_methods, which(reenable_sigint, Tuple{Function}))
    # Signal-handling in the `print` dispatch hierarchy
    push!(compiled_methods, which(Base.unsafe_write, Tuple{Base.LibuvStream, Ptr{UInt8}, UInt}))
    # Libc.GetLastError()
    @static if Sys.iswindows()
        push!(compiled_methods, which(Base.access_env, Tuple{Function, AbstractString}))
        push!(compiled_methods, which(Base._hasenv, Tuple{Vector{UInt16}}))
    end
end

function __init__()
    set_compiled_methods()
end

include("precompile.jl")
_precompile_()

end # module
