import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t, bool32_t, ray_t # Base SK types
using Printf, IMisc

# --- Helpers ---

const cm2m = 0.01f0
const mm2m = 0.001f0
const vec3_zero = vec3(0,0,0)

Base.:(*)(a::vec3, b::vec3)::vec3 = vec3(a.x*b.x, a.y*b.y, a.z*b.z)
Base.:(+)(a::vec3, b::vec3)::vec3 = vec3(a.x+b.x, a.y+b.y, a.z+b.z)

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

# --- App ---

const white = color128(1, 1, 1, 1)
const black = color128(0, 0, 0, 1)
const gray = color128(0.5, 0.5, 0.5, 1)
const transparent_black = color128(0, 0, 0, 0)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const OBJ_POS = vec3(-0.25, 0, -0.5)
const OBJ_ORI = SK.quat_from_angles(22, 90, 22)
const OBJ_SCALE = vec3(0.25, 0.25, 0.35)
const floor_transform = Ref(SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(quat_identity), Ref(vec3(30, 0.1, 30))))
const X_RANGE = -0.75:0.01:0.75
const Y_RANGE = -0.75:0.01:0.25
const Z_RANGE = -2.5:0.01:-0.5
const TARGET_FPS = 59

@kwdef mutable struct FrameStats
    framecount::Int = 0
    frametime::Float64 = time()
    fps::Float32 = 0
    time::Float64 = 0
    bytes::Int64 = 0
    allocs::Int64 = 0
    gctime::Float64 = 0
    avtimems::Float32 = 0
    avbytes::Int = 0
    avallocs::Int = 0
    avgctimems::Float32 = 0
end

@kwdef mutable struct RenderState 
    floor_model::SK.model_t = C_NULL
    obj_model::SK.model_t = SK.model_t(C_NULL)
    window_pos::vec3 = vec3(0.0, -0.05, -0.3)
    obj_ang::Float32 = 0
    stats::FrameStats = FrameStats()
    objinfos::Vector{ray_t} = ray_t[]
end

randAngle() = rand() * 360

function addObj(rs::RenderState)
    oi = ray_t(vec3(rand(X_RANGE), rand(Y_RANGE), rand(Z_RANGE)), vec3(randAngle(), randAngle(), randAngle()))
    push!(rs.objinfos, oi)
end

function updatefps(rs::RenderState)::Void
    fs = rs.stats
    fs.framecount += 1
    delta = time() - fs.frametime
    if delta > 1.0
        fs.fps = fs.framecount / delta
        fs.avallocs = fs.allocs ÷ fs.framecount
        fs.avbytes = fs.bytes ÷ fs.framecount
        fs.avgctimems = round((fs.gctime * 1000) / fs.framecount, digits=2)
        fs.avtimems = round((fs.time * 1000) / fs.framecount, digits=2)
        fs.framecount = fs.allocs = fs.bytes = fs.gctime = fs.time = 0
        fs.frametime = time()
    end
end

function updatetime(fs::FrameStats, stats)::Void
    fs.time += stats.time
    fs.bytes += stats.bytes
    fs.allocs += stats.gcstats.poolalloc + stats.gcstats.malloc + stats.gcstats.realloc + stats.gcstats.bigalloc
    fs.gctime += stats.gctime
end

col_from_pos(x, y, z) = color128(x-X_RANGE[begin], y-Y_RANGE[begin], z-Z_RANGE[begin], 1.0)
col_from_pos(v::vec3) = col_from_pos(v.x, v.y, v.z)

function render(rs::RenderState)::Void 
    stats = @timed try 
        SK.render_add_model(rs.floor_model, floor_transform, white, SK.render_layer_0)
        
        head_pose = SK.input_head() |> unsafe_load
        window_pose = Ref(SK.pose_t(rs.window_pos, SK.quat_lookat(Ref(rs.window_pos), Ref(head_pose.position))))
        fps = round(rs.stats.fps; digits=1)
        SK.ui_window_begin("--- Information ---", window_pose, vec2(7cm2m, 2cm2m), SK.ui_win_normal, SK.ui_move_face_user)
        SK.ui_text(
            """
            Objs:        $(length(rs.objinfos))
            FPS:         $fps
            Render:   $(rs.stats.avtimems) ms                  
            Allocs:     $(rs.stats.avallocs)     
            Bytes:      $(rs.stats.avbytes)             
            GC:          $(rs.stats.avgctimems) ms
            """, 
            SK.text_align_center_left) # 14 allocs
        SK.ui_window_end()
        rs.window_pos = window_pose[].position

        rs.obj_ang += 0.2
        if (rs.obj_ang > 360) rs.obj_ang = 0 end

        for objinfo in rs.objinfos
            ori = SK.quat_from_angles(objinfo.dir.x, objinfo.dir.y + rs.obj_ang, objinfo.dir.z)
            m = SK.matrix_trs(Ref(objinfo.pos), Ref(ori), Ref(OBJ_SCALE))
            SK.model_draw(rs.obj_model, m, col_from_pos(objinfo.pos), SK.render_layer_0)
        end

        # instfps = rs.stats.framecount / (time() - rs.stats.frametime) 
        # if (instfps >= TARGET_FPS) addObj(rs) end
        if (fps >= TARGET_FPS) addObj(rs) end
        updatefps(rs)
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
    
    rs.obj_model = SK.model_create_file("SpaceShuttle.glb", SK.shader_t(C_NULL))
end

async(f::Function, isasync::Bool)::Void = (isasync ? @async(f()) : f())

# --- Main --- 

sk_init(app_name = "Test Perf", assets_folder = "assets")
rs = RenderState()
loadassets(rs)

# Async if in vscode, sync otherwise
async(isinteractive()) do
    sk_renderloop(() -> render(rs))
    # ... cleanup assets ...
    SK.sk_shutdown()
end

