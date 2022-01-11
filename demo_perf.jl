import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t, bool32_t # Base SK types
using Printf, IMisc

# --- Helpers ---
Base.transcode(::Type{Cchar}, s::String) = reinterpret(Cchar, transcode(UInt8, s))
macro u8_str(s) transcode(Cchar, s) end
macro u16_str(s) transcode(char16_t, s) end
const cm2m = 0.01f0
const mm2m = 0.001f0
const vec3_zero = vec3(0,0,0)

Base.:(*)(l::vec3, r::vec3)::vec3 = vec3(l.x*r.x, l.y*r.y, l.z*r.z)

function sk_renderloop(render::Function)::Void
    render_wrapper() = try render() catch end # Eat exceptions
    render_wrapper_c = @cfunction($render_wrapper, Void, ()) # Not supported on all cpu architectures
    if isinteractive()
        while SK.sk_step(render_wrapper_c) > 0
            sleep(0.01)
        end
    else
        while SK.sk_step(render_wrapper_c) > 0 end
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
    disable_flatscreen_mr_sim::Bool = false)

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
            C_NULL, C_NULL)
        SK.sk_init(settings)
    end
end

# --- App ---
const white = color128(1, 1, 1, 1)
const black = color128(0, 0, 0, 1)
const gray = color128(0.5, 0.5, 0.5, 1)
const transparent_black = color128(0, 0, 0, 0)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const model_pos = vec3(-0.25, 0, -0.5)
const model_ori = SK.quat_from_angles(22, 90, 22)
# const model_scale = vec3(0.005, 0.005, 0.005)
const model_scale = vec3(1, 1, 1)
const floor_transform = Ref(SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(quat_identity), Ref(vec3(30, 0.1, 30))))

@kwdef mutable struct FrameStats
    framecount::Int = 0
    frametime::Float64 = 0
    fps::Float32 = 0
    time::Float64 = 0
    bytes::Int64 = 0
    allocs::Int64 = 0
    gctime::Float64 = 0
end

@kwdef mutable struct RenderState 
    floor_model::SK.model_t = C_NULL
    model_model::SK.model_t = SK.model_t(C_NULL)
    model_pose::Ref{SK.pose_t} = Ref(SK.pose_t(model_pos, model_ori))
    model_bounds::SK.bounds_t = SK.bounds_t(vec3_zero, vec3_zero)
    window_pos::vec3 = vec3(0.1, 0.2, -0.2)
    stats::FrameStats = FrameStats()
end

function updatefps(fs::FrameStats)::Void
    fs.framecount += 1
    delta = time() - fs.frametime
    if delta > 1.0
        fs.fps = fs.framecount / delta
        fs.framecount = 0
        fs.frametime = time()
    end
end

function updatetime(fs::FrameStats, stats)::Void
    fs.time = stats.time
    fs.bytes = stats.bytes
    fs.allocs = stats.gcstats.poolalloc + stats.gcstats.malloc + stats.gcstats.realloc + stats.gcstats.bigalloc
    fs.gctime = stats.gctime
end

function render(rs::RenderState)::Void 
    stats = @timed try
        SK.render_add_model(rs.floor_model, floor_transform, white, SK.render_layer_0)
        
        head_pose = SK.input_head() |> unsafe_load
        window_pose = Ref(SK.pose_t(rs.window_pos, SK.quat_lookat(Ref(rs.window_pos), Ref(head_pose.position))))
        fps = round(rs.stats.fps; digits=1)
        SK.ui_window_begin("Information", window_pose, vec2(7cm2m, 2cm2m), SK.ui_win_normal, SK.ui_move_face_user)
        SK.ui_text("FPS:      $fps \nAllocs:  $(rs.stats.allocs) \nBytes:   $(rs.stats.bytes) \nGC:       $(rs.stats.gctime)ms", SK.text_align_center_left)
        SK.ui_window_end()
        rs.window_pos = window_pose[].position

        SK.ui_handle_begin("model", rs.model_pose, rs.model_bounds, 0, SK.ui_move_exact)
        SK.ui_handle_end()
        m = SK.matrix_trs(Ref(rs.model_pose[].position), Ref(rs.model_pose[].orientation), Ref(model_scale))
        SK.model_draw(rs.model_model, m, white, SK.render_layer_0)

        updatefps(rs.stats)
    catch e
        println("Exception: $e in $(stacktrace(catch_backtrace())[1])")
        sleep(0.5)
    end
    updatetime(rs.stats, stats) 
end

function loadassets(rs::RenderState)::Void
    floor_mesh = SK.mesh_find("default/mesh_cube")
    floor_material = SK.shader_create_file("floor.hlsl") |> SK.material_create
    SK.material_set_transparency(floor_material, SK.transparency_blend)
    rs.floor_model = SK.model_create_mesh(floor_mesh, floor_material)

    # model_shader = SK.shader_create_file("floor.hlsl")
    # rs.model_model = SK.model_create_file("SpaceShuttle.glb", model_shader)

    # matPBR = Default.MaterialPBR.Copy();
    # matPBR[MatParamName.DiffuseTex  ] = Tex.FromFile("metal_plate_diff.jpg");
    # matPBR[MatParamName.MetalTex    ] = Tex.FromFile("metal_plate_metal.jpg", false);
    # matPBR[MatParamName.OcclusionTex] = Tex.FromFile("metal_plate_metal.jpg", false);
    texdiff = SK.tex_create_file("metal_plate_diff.jpg", true)
    texmet = SK.tex_create_file("metal_plate_metal.jpg", false)
    texocc = SK.tex_create_file("metal_plate_metal.jpg", false)
    shader = SK.shader_find("default/shader_pbr")
    mat = SK.material_create(shader)
    SK.material_set_texture(mat, "diffuse", texdiff)
    SK.material_set_texture(mat, "metallic", texmet)
    SK.material_set_texture(mat, "occlusion", texocc)
    mesh = SK.mesh_gen_rounded_cube(vec3(0.25, 0.25, 0.25), 0.02, 4)
    rs.model_model = SK.model_create_mesh(mesh, mat)
    
    # rs.model_model = SK.model_create_file("SpaceShuttle.glb", SK.shader_t(C_NULL))
    # rs.model_model = SK.model_create_file("MarsCuriosityRover.glb", SK.shader_t(C_NULL))
    # rs.model_model = SK.model_create_file("DamagedHelmet.gltf", SK.shader_t(C_NULL))
    # rs.model_model = SK.model_create_file("Cosmonaut.glb", SK.shader_t(C_NULL))

    bounds = SK.model_get_bounds(rs.model_model)
    rs.model_bounds = SK.bounds_t(bounds.center, bounds.dimensions * model_scale)
    # @show bounds
end

async(f::Function, isasync::Bool)::Void = (isasync ? @async(f()) : f())

sk_init(app_name = "Test App", assets_folder = "assets")
rs = RenderState()
loadassets(rs)

# Async if in vscode, sync otherwise
async(isinteractive()) do
    sk_renderloop(() -> render(rs))
    # ... cleanup assets ...
    SK.sk_shutdown()
end
    