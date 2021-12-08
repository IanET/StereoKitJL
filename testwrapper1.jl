import LibStereoKit as SK
import Base.@kwdef

macro a_str(s) transcode(UInt8, s) .|> Cchar end
macro a16_str(s) transcode(UInt16, s) .|> SK.char16_t end

const appname = a"Project"
const asset_folder = a"assets"
const white = SK.color128(1, 1, 1, 1)
const blueish = SK.color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)

@kwdef mutable struct RenderState 
    cube_model::SK.model_t = C_NULL
    cube_pose_r::Ref{SK.pose_t} = Ref(SK.pose_t(SK.vec3(0, 0, -0.5), quat_identity))
    floor_mesh::SK.mesh_t = C_NULL
    floor_transform::SK.matrix = SK.matrix_trs(Ref(SK.vec3(0, -1.5, 0)), Ref(quat_identity), Ref(SK.vec3(30, 0.1, 30)))
    floor_material = C_NULL
end

const rs = RenderState()
const render_rs() = render(rs)
const render_rs_c = @cfunction(render_rs, Nothing, ())

function render(rs::RenderState) 
    SK.render_add_mesh(rs.floor_mesh, rs.floor_material, Ref(rs.floor_transform), white, SK.render_layer_0)
    bounds = SK.model_get_bounds(rs.cube_model)
    SK.ui_handle_begin_16(a16"Cube", rs.cube_pose_r, bounds, 0, SK.ui_move_exact)
    SK.ui_handle_end()
    matrix = SK.matrix_trs(
        Ref(rs.cube_pose_r[].position), 
        Ref(rs.cube_pose_r[].orientation), 
        Ref(SK.vec3(1, 1, 1)))
    SK.render_add_model(rs.cube_model, Ref(matrix), blueish, SK.render_layer_0)
end

function main(rs::RenderState)
    GC.@preserve appname asset_folder begin 
        settings = SK.sk_settings_t(
            pointer(appname),
            pointer(asset_folder),
            SK.display_mode_flatscreen,
            SK.display_blend_any_transparent,
            0,
            SK.depth_mode_balanced,
            SK.log_none,
            0, 0, 0, 0, 0, 0, 0, C_NULL, C_NULL)
        SK.sk_init(settings) 
    end

    material = SK.material_find(a"default/material")
    mesh = SK.mesh_gen_rounded_cube(SK.vec3(0.25, 0.25, 0.25), 0.02, 4)
    rs.cube_model = SK.model_create_mesh(mesh, material)

    rs.floor_mesh = SK.mesh_find(a"default/mesh_cube")
    rs.floor_transform = SK.matrix_trs(Ref(SK.vec3(0, -1.5, 0)), Ref(quat_identity), Ref(SK.vec3(30, 0.1, 30)))
    rs.floor_material = SK.shader_create_file(a"floor.hlsl") |> SK.material_create
    SK.material_set_transparency(rs.floor_material, SK.transparency_blend)

    while SK.sk_step(render_rs_c) > 0 end

    SK.sk_shutdown()
end

main(rs)

