package game

import rl "vendor:raylib"
import "core:strings"
import "core:c"
import "core:fmt"

UniformValue :: union {
    f32, i32, [2]f32, [][2]f32, rl.Texture, [4]f32, [3]f32, [][4]f32
}

ShaderInterface :: struct {
    shader: rl.Shader,
    uniforms: map[string] UniformValue,
    uniform_locs: map[string] c.int,

    vertex, fragment : cstring,
    last_modified_time: c.long
}

load_shader :: proc(vertex: cstring, fragment: cstring) -> ShaderInterface {
    interface := ShaderInterface {
        shader = rl.LoadShader(vertex, fragment),
        vertex = vertex,
        fragment = fragment
    }
    interface.uniforms = make(map[string]UniformValue)
    interface.uniform_locs = make(map[string]c.int)

    files := []cstring {vertex, fragment}
    for file in files {
        if file == nil do continue
        mod_time := rl.GetFileModTime(file)
        if mod_time > interface.last_modified_time {
            interface.last_modified_time = mod_time
        }
    }

    return interface
}

temp_shader :: proc(from: ShaderInterface) -> ^ShaderInterface {
    context.allocator = context.temp_allocator
    interface := new(ShaderInterface)
    interface.shader = from.shader
    interface.uniforms = make(map[string]UniformValue)
    interface.uniform_locs = make(map[string]c.int)
    return interface
}

interface_check_reload :: proc(interface: ^ShaderInterface){

    files := []cstring { interface.vertex, interface.fragment }
    for file in files {
        if file == nil do continue
        last_modified_time := rl.GetFileModTime(file)
        if last_modified_time > interface.last_modified_time {
            clear(&interface.uniforms)
            clear(&interface.uniform_locs)
            new_shader := rl.LoadShader(interface.vertex, interface.fragment)
            if new_shader == {} do return
            interface.shader = new_shader
            interface.last_modified_time = last_modified_time
            return
        }
    }
}

interface_set_uniforms :: proc(interface: ^ShaderInterface){
    for key, &value in interface.uniforms {


        location, found := interface.uniform_locs[key]
        if !found {
            cstring_key := strings.clone_to_cstring(key, context.temp_allocator)
            location = rl.GetShaderLocation(interface.shader, cstring_key)
            interface.uniform_locs[key] = location
        }

        switch &v in value {
            case i32:
                rl.SetShaderValue(interface.shader, location, &v, .INT)
            case f32:
                rl.SetShaderValue(interface.shader, location, &v, .FLOAT)
            case [2]f32:
                rl.SetShaderValue(interface.shader, location, &v, .VEC2)
            case [3]f32:
                rl.SetShaderValue(interface.shader, location, &v, .VEC3)
            case [4]f32:
                rl.SetShaderValue(interface.shader, location, &v, .VEC4)

            case [][2]f32:
                count := i32(len(v))
                count_key := fmt.ctprintf("%s_count", key)
                count_loc := rl.GetShaderLocation(interface.shader, count_key)
                rl.SetShaderValueV(interface.shader, location, &v[0], .VEC2, count)
                rl.SetShaderValue(interface.shader, count_loc, &count, .INT)
            case [][4]f32:
                count := i32(len(v))
                count_key := fmt.ctprintf("%s_count", key)
                count_loc := rl.GetShaderLocation(interface.shader, count_key)
                rl.SetShaderValueV(interface.shader, location, &v[0], .VEC4, count)
                rl.SetShaderValue(interface.shader, count_loc, &count, .INT)

            case rl.Texture:
                rl.SetShaderValueTexture(interface.shader, location, v)

        }
    }
}

@(deferred_none=rl.EndShaderMode)
with_shader :: proc(interface: ^ShaderInterface) -> bool {
    rl.BeginShaderMode(interface.shader)
    interface_set_uniforms(interface)
    return true
}