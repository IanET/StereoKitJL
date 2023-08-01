using Printf, IMisc

import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t, bool32_t # Base SK types

include("common.jl")

@kwdef mutable struct RenderState 
    cube_model::SK.model_t = C_NULL
    cube_pose_r::Ref{SK.pose_t} = Ref(SK.pose_t(vec3(0, 0, -0.5), QUAT_IDENTITY))
    floor_transform::SK.matrix = SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(QUAT_IDENTITY), Ref(vec3(30, 0.1, 30)))
    floor_model::SK.model_t = C_NULL
end

function render(rs::RenderState) 
    try
        SK.render_add_model(rs.floor_model, Ref(rs.floor_transform), COLOR_WHITE, SK.render_layer_0)
        bounds = SK.model_get_bounds(rs.cube_model)
        SK.ui_handle_begin("Cube", rs.cube_pose_r, bounds, 0, SK.ui_move_exact)
        SK.ui_handle_end()
        matrix = SK.matrix_trs(Ref(rs.cube_pose_r[].position), Ref(rs.cube_pose_r[].orientation), Ref(vec3(1, 1, 1)))
        SK.render_add_model(rs.cube_model, Ref(matrix), COLOR_BLUEISH, SK.render_layer_0)
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

