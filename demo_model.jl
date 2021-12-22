import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t # Base SK types
using Printf, IMisc

Base.transcode(::Type{Cchar}, s::String) = reinterpret(Cchar, transcode(UInt8, s))
macro u8_str(s) transcode(Cchar, s) end
macro u16_str(s) transcode(char16_t, s) end

# NB Keep as global const so they don't get GC'd (unsafe ptr below)
const appname = u8"Project"
const asset_folder = u8"assets"

const white = color128(1, 1, 1, 1)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const cm2m = 0.01f0
const mm2m = 0.001f0
const rval = Ref(0.5f0)
const rval2 = Ref(0.5f0)
const vec3_zero = vec3(0,0,0)

const helmet_pos = vec3(-0.25, 0, -0.5)
const helmet_ori = SK.quat_from_angles(20, 170, 0)
const helmet_scale = vec3(0.2, 0.2, 0.2)
const floor_transform = Ref(SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(quat_identity), Ref(vec3(30, 0.1, 30))))

Base.:(*)(l::vec3, r::vec3)::vec3 = vec3(l.x*r.x, l.y*r.y, l.z*r.z)

@kwdef mutable struct RenderState 
    floor_model::SK.model_t = C_NULL
    helmet_model::SK.model_t = SK.model_t(C_NULL)
    helmet_pose::Ref{SK.pose_t} = Ref(SK.pose_t(helmet_pos, helmet_ori))
    helmet_bounds::SK.bounds_t = SK.bounds_t(vec3_zero, vec3_zero)
    window_pos = vec3(0.1, 0.2, -0.2)
    framecount::Int = 0
    frametime::Float64 = 0
    fps::Float32 = 0
end

function updatefps(rs::RenderState)::Void
    rs.framecount += 1
    delta = time() - rs.frametime
    if delta > 1.0
        rs.fps = rs.framecount / delta
        rs.framecount = 0
        rs.frametime = time()
    end
end

# TODO - fix ref allocs (21, 928 bytes) 
function render(rs::RenderState)::Void 
    try
        SK.render_add_model(rs.floor_model, floor_transform, white, SK.render_layer_0)
        
        head_pose = SK.input_head() |> unsafe_load
        window_pose = Ref(SK.pose_t(rs.window_pos, SK.quat_lookat(Ref(rs.window_pos), Ref(head_pose.position))))
        SK.ui_window_begin("Information", window_pose, vec2(7cm2m, 2cm2m), SK.ui_win_normal, SK.ui_move_face_user)
        fps = round(rs.fps; digits=1)
        SK.ui_text("FPS: $fps", SK.text_align_center_left)
        SK.ui_window_end()
        rs.window_pos = window_pose[].position

        SK.ui_handle_begin("helmet", rs.helmet_pose, rs.helmet_bounds, 0, SK.ui_move_exact)
        SK.ui_handle_end()
        m = SK.matrix_trs(
            Ref(rs.helmet_pose[].position), 
            Ref(rs.helmet_pose[].orientation), 
            Ref(helmet_scale))
        SK.model_draw(rs.helmet_model, m, white, SK.render_layer_0)
        updatefps(rs)
    catch e
        println("Exception: $e")
        sleep(0.5)
    end
end

const grs = RenderState()
const render_grs() = render(grs)
const render_grs_c = @cfunction(render_grs, Void, ())

function renderloop(render_rs_c)::Void
    if isinteractive()
        while SK.sk_step(render_rs_c) > 0
            sleep(0.01)
        end
    else
        while SK.sk_step(render_rs_c) > 0 end
    end
    SK.sk_shutdown()
end

function initsk()::Void
    settings = SK.sk_settings_t(
        pointer(appname),
        pointer(asset_folder),
        # SK.display_mode_mixedreality,
        SK.display_mode_flatscreen,
        SK.display_blend_any_transparent,
        0,
        SK.depth_mode_balanced,
        SK.log_diagnostic,
        0, 0, 0, 0, 0, 0, 0, C_NULL, C_NULL)
    SK.sk_init(settings) 
end

function loadassets(rs::RenderState)::Void
    rs.helmet_model = SK.model_create_file("DamagedHelmet.gltf", SK.shader_t(C_NULL))
    bounds = SK.model_get_bounds(rs.helmet_model)
    rs.helmet_bounds = SK.bounds_t(bounds.center, bounds.dimensions * helmet_scale)

    floor_mesh = SK.mesh_find("default/mesh_cube")
    floor_material = SK.shader_create_file("floor.hlsl") |> SK.material_create
    SK.material_set_transparency(floor_material, SK.transparency_blend)
    rs.floor_model = SK.model_create_mesh(floor_mesh, floor_material)
end

function main(rs::RenderState)::Void
    initsk()
    loadassets(rs)

    if isinteractive()
        @async renderloop(render_grs_c)
    else
        renderloop(render_grs_c)
    end

end

main(grs)
