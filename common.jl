const cm2m = 0.01f0
const mm2m = 0.001f0

const COLOR_WHITE = color128(1, 1, 1, 1)
const COLOR_BLACK = color128(0, 0, 0, 1)
const COLOR_GREY = color128(0.5, 0.5, 0.5, 1)
const COLOR_TRANSPARENT_BLACK = color128(0, 0, 0, 0)
const COLOR_BLUEISH = color128(0.5, 0.6, 0.7, 1.0)
const QUAT_IDENTITY = SK.quat(0, 0, 0, 1)

Base.:(*)(a::vec3, b::vec3)::vec3 = vec3(a.x*b.x, a.y*b.y, a.z*b.z)
Base.:(+)(a::vec3, b::vec3)::vec3 = vec3(a.x+b.x, a.y+b.y, a.z+b.z)
vec3() = vec3(0, 0, 0)
vec3(v) = vec3(v, v, v)

function sk_renderloop(render::Function)::Void
    render_wrapper() = try render() catch end # Eat exceptions
    render_wrapper_c = @cfunction($render_wrapper, Void, ()) # Not supported on all cpu architectures
    if isinteractive()
        while SK.sk_step(render_wrapper_c) > 0; sleep(0.01) end
    else
        while SK.sk_step(render_wrapper_c) > 0; end
    end
end

function sk_init(;
    app_name::String = "",
    assets_folder::String = "",
    display_preference::SK.display_mode_ = SK.display_mode_mixedreality,
    blend_preference::SK.display_blend_ = SK.display_blend_any_transparent,
    no_flatscreen_fallback::Bool = false,
    depth_mode::SK.depth_mode_ = SK.depth_mode_balanced,
    log_filter::SK.log_ = SK.log_diagnostic,
    overlay_app::Bool = false,
    overlay_priority::Int = 0, 
    flatscreen_pos_x::Int = 0,
    flatscreen_pos_y::Int = 0, 
    flatscreen_width::Int = 0, 
    flatscreen_height::Int = 0, 
    disable_flatscreen_mr_sim::Bool = false,
    disable_unfocused_sleep::Bool = true)

    GC.@preserve app_name assets_folder begin 
        settings = SK.sk_settings_t(
            pointer(app_name),
            pointer(assets_folder),
            display_preference,
            blend_preference,
            no_flatscreen_fallback |> bool32_t,
            depth_mode,
            log_filter,
            overlay_app,
            overlay_priority |> UInt32,
            flatscreen_pos_x |> Int32,
            flatscreen_pos_y |> Int32,
            flatscreen_width |> Int32,
            flatscreen_height |> Int32,
            disable_flatscreen_mr_sim |> bool32_t,
            disable_unfocused_sleep |> bool32_t,
            C_NULL, 
            C_NULL
        )
        SK.sk_init(settings)
    end
end
