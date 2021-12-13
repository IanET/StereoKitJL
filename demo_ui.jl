import LibStereoKit as SK
import Base.@kwdef
import LibStereoKit: vec2, vec3, quat, color128, char16_t # Base SK types

Base.transcode(::Type{Cchar}, s::String) = reinterpret(Cchar, transcode(UInt8, s))
macro u8_str(s) transcode(Cchar, s) end
macro u16_str(s) transcode(char16_t, s) end

const appname = u8"Project"
const asset_folder = u8"assets"
const white = color128(1, 1, 1, 1)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const window_pose = SK.pose_t(vec3(0, 0.28, -0.25), SK.quat_lookat(Ref(vec3(0, 0, -0.25)), Ref(vec3(0, 0.1, 0))))
const cm2m = 0.01f0
const mm2m = 0.001f0
const rval = Ref(0.5f0)
const rval2 = Ref(0.5f0)
const helmet_pose_matrix = SK.matrix_trs(
    Ref(vec3(-0.25, 0, -0.5)), 
    Ref(quat_identity), 
    Ref(vec3(0.25, 0.25, 0.25)))

@kwdef mutable struct RenderState 
    ui_sprite::SK.sprite_t = SK.sprite_t(C_NULL)
    buffer::Vector{Cchar} = zeros(Cchar, 128)
    helmet::SK.model_t = SK.model_t(C_NULL)
end

const grs = RenderState()
const render_rs() = render(grs)
const render_rs_c = @cfunction(render_rs, Nothing, ())

function render(rs::RenderState) 
    SK.ui_window_begin("Main", Ref(window_pose), vec2(24cm2m, 24cm2m), SK.ui_win_normal, SK.ui_move_face_user)
    SK.ui_button("Testing!")
    SK.ui_sameline()
    SK.ui_input("text", pointer(rs.buffer), sizeof(rs.buffer), vec2(16cm2m, SK.ui_line_height()))
    SK.ui_hslider("slider", rval, 0.0, 1.0, 0.2, 72mm2m, SK.ui_confirm_pinch)
    SK.ui_sameline()
    SK.ui_hslider("slider2", rval2, 0.0, 1.0, 0.0, 72mm2m, SK.ui_confirm_push)
    if SK.input_key(SK.key_mouse_left) & SK.button_state_active > 0
        SK.ui_image(rs.ui_sprite, vec2(6cm2m, 0cm2m))
    end
    if SK.ui_button("Press me!") > 0
        SK.ui_button("DYNAMIC BUTTON!!")
    end
    SK.ui_text("古池や 蛙飛び込む 水の音 - Matsuo Basho", SK.text_align_top_left)
    # SK.ui_text("Съешь же ещё этих мягких французских булок да выпей чаю. Широкая электрификация южных губерний даст мощный толчок подъёму сельского хозяйства. В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!", SK.text_align_top_left)
    SK.ui_window_end()
    SK.model_draw(rs.helmet, helmet_pose_matrix, white, SK.render_layer_0)
end

function main(rs::RenderState)
    # GC preserve?
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

	rs.ui_sprite = SK.sprite_create_file("StereoKitWide.png", SK.sprite_type_single, "default")
    rs.helmet = SK.model_create_file("DamagedHelmet.gltf", SK.shader_t(C_NULL))

    if isinteractive()
        @async begin
            while SK.sk_step(render_rs_c) > 0
                sleep(0.1)
            end
            SK.sk_shutdown()
        end
    else
        while SK.sk_step(render_rs_c) > 0 end
        SK.sk_shutdown()
    end
end

main(grs)









