import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t, bool32_t # Base SK types
import Base.@kwdef

using Printf, IMisc

# HACK, Julia strings are UTF8 internally
# Base.transcode(::Type{Cchar}, s::String) = reinterpret(Cchar, transcode(UInt8, s))
# macro c8_str(s) transcode(Cchar, s) end
# macro c16_str(s) transcode(char16_t, s) end

const WHITE = SK.color128(1, 1, 1, 1)
const BLUEISH = SK.color128(0.5, 0.6, 0.7, 1.0)
const QUAT_IDENTITY = SK.quat(0, 0, 0, 1)

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
    disable_unfocused_sleep::Bool = false)

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

@kwdef mutable struct RenderState 
    cube_model::SK.model_t = C_NULL
    cube_pose_r::Ref{SK.pose_t} = Ref(SK.pose_t(vec3(0, 0, -0.5), QUAT_IDENTITY))
    floor_transform::SK.matrix = SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(QUAT_IDENTITY), Ref(vec3(30, 0.1, 30)))
    floor_model::SK.model_t = C_NULL
end

# const grs = RenderState()
# const render_rs() = render(grs)
# const render_rs_c = @cfunction(render_rs, Nothing, ())

function render(rs::RenderState) 
    try
        SK.render_add_model(rs.floor_model, Ref(rs.floor_transform), WHITE, SK.render_layer_0)
        bounds = SK.model_get_bounds(rs.cube_model)
        SK.ui_handle_begin("Cube", rs.cube_pose_r, bounds, 0, SK.ui_move_exact)
        SK.ui_handle_end()
        matrix = SK.matrix_trs(Ref(rs.cube_pose_r[].position), Ref(rs.cube_pose_r[].orientation), Ref(vec3(1, 1, 1)))
        SK.render_add_model(rs.cube_model, Ref(matrix), BLUEISH, SK.render_layer_0)
    catch exc
        println("Exception: $exc")
    end
end

function main()
    rs = RenderState()

    sk_init(app_name = "Cube Test App", assets_folder = "assets")

    material = SK.material_find("default/material")
    mesh = SK.mesh_gen_rounded_cube(vec3(0.25, 0.25, 0.25), 0.02, 4)
    rs.cube_model = SK.model_create_mesh(mesh, material)

    floor_mesh = SK.mesh_find("default/mesh_cube")
    floor_material = SK.shader_create_file("floor.hlsl") |> SK.material_create
    SK.material_set_transparency(floor_material, SK.transparency_blend)
    rs.floor_model = SK.model_create_mesh(floor_mesh, floor_material)

    render_rs() = render(rs)
    render_rs_c = @cfunction($render_rs, Nothing, ())

    while SK.sk_step(render_rs_c) > 0 end

    SK.sk_shutdown()
end

main()

