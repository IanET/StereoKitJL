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

@kwdef mutable struct RenderState 
    ui_sprite::SK.sprite_t = SK.sprite_t(C_NULL)
    buffer::Vector{Cchar} = zeros(Cchar, 128)
    helmet::SK.model_t = SK.model_t(C_NULL)
    helmet_pos::Ref{vec3} = Ref(vec3(-0.25, 0, -0.5))
    helmet_ori::Ref{quat} = Ref(SK.quat_from_angles(20, 170, 0))
    helmet_scale::Ref{vec3} = Ref(vec3(0.2, 0.2, 0.2))
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

function render(rs::RenderState)::Void 
    head_pose = SK.input_head() |> unsafe_load
    window_pos = vec3(0.1, 0.2, -0.2)
    window_pose = SK.pose_t(window_pos, SK.quat_lookat(Ref(window_pos), Ref(head_pose.position)))
    SK.ui_window_begin("Information", Ref(window_pose), vec2(7cm2m, 2cm2m), SK.ui_win_normal, SK.ui_move_face_user)
    fps = round(rs.fps; digits=1)
    SK.ui_text("FPS: $fps", SK.text_align_center_left)
    SK.ui_window_end()
    pose = SK.matrix_trs(rs.helmet_pos, rs.helmet_ori, rs.helmet_scale)
    SK.model_draw(rs.helmet, pose, white, SK.render_layer_0)
    updatefps(rs)
end

const grs = RenderState()
const render_grs() = render(grs)
const render_grs_c = @cfunction(render_grs, Void, ())

sleep_optional(t) = t > 0 ? sleep(t) : nothing

function renderloop(render_rs_c, sleeptime = 0)::Void
    while SK.sk_step(render_rs_c) > 0
        sleep_optional(sleeptime)
    end
end

function initsk()::Void
    settings = SK.sk_settings_t(
        pointer(appname),
        pointer(asset_folder),
        SK.display_mode_flatscreen,
        SK.display_blend_any_transparent,
        0,
        SK.depth_mode_balanced,
        SK.log_diagnostic,
        0, 0, 0, 0, 0, 0, 0, C_NULL, C_NULL)
    SK.sk_init(settings) 
end

function loadassets(rs::RenderState)::Void
    rs.ui_sprite = SK.sprite_create_file("StereoKitWide.png", SK.sprite_type_single, "default")
    rs.helmet = SK.model_create_file("DamagedHelmet.gltf", SK.shader_t(C_NULL))
end

function main(rs::RenderState)::Void
    initsk()
    loadassets(rs)

    if isinteractive()
        @async begin 
            renderloop(render_grs_c, 0.01)
            SK.sk_shutdown()
        end
    else
        renderloop(render_grs_c)
        SK.sk_shutdown()
    end

end

main(grs)
