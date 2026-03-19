package game
import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:slice"

Circle :: struct {
    centre: [2]f32,
    radius: f32,
}

DrawTexture :: struct {
    position: [2]f32,
    type: TextureType,
    frame: int,
    scale: [2]f32,
    rotation: f32
}

DrawLine :: struct {
    line: [2][2]f32,
    color: rl.Color,
    thickness: f32,
    rounded: bool
}

DrawCircle :: struct {
    circle: Circle,
    scale: f32,
    fill, line: rl.Color
}

DrawRect :: struct {
    rect: Rect,
    fill, line: rl.Color
}

Clip :: struct {
    begin: bool,
    rect: Rect,
}


@(deferred_in = shadow_end)
shadow_begin :: proc(layer: Layer, height: f32){
    state.ui_state.shadow_start = len(state.draw_commands[layer])
}

shadow_end :: proc(layer: Layer, height: f32){
    SHADOW_COLOR :: rl.Color { 0, 0, 0, 100 }
    shadow_commands := state.draw_commands[layer][state.ui_state.shadow_start:]
    shadow_commands = slice.clone(shadow_commands, context.temp_allocator)
    for command in shadow_commands {
        #partial switch v in command {
        case DrawRect:
            command := v
            command.rect += { height, height, 0, 0, }
            command.fill = SHADOW_COLOR
            inject_at(&state.draw_commands[layer], state.ui_state.shadow_start, command)
        case DrawLine:
            command := v
            command.line += height
            command.color = SHADOW_COLOR
            inject_at(&state.draw_commands[layer], state.ui_state.shadow_start, command)
        }

    }
}

clip_rect_begin :: proc(layer: Layer, rect: Rect) {
    append(&state.draw_commands[layer], Clip { true, rect })
}
clip_rect_end :: proc(layer: Layer) {
    append(&state.draw_commands[layer], Clip { false, {} })
}

TextFlag :: enum {
    Wrap,
    Centre,
    NoClone,
}

DrawText :: struct {
    text: string, // copied
    rect: Rect,
    color: rl.Color,
    font: rl.Font,
    scale: f32,
    flags: bit_set[TextFlag],
    display_length: int,
}

DrawCommand :: union {
    DrawCircle, DrawRect, DrawTexture, DrawText, Clip, DrawLine
}


Layer :: enum {
    Low, Middle, High, UI
}

draw_circle :: proc(layer: Layer, circle: Circle, fill, line: rl.Color){
    command: DrawCommand = DrawCircle {circle, 1, fill, line }
    append(&state.draw_commands[layer], command)
}

draw_line :: proc(layer: Layer, line: [2][2]f32, color: rl.Color, thickness: f32, rounded: bool = false) {
    command: DrawCommand = DrawLine { line, color, thickness, rounded }
    append(&state.draw_commands[layer], command)
}

draw_rect :: proc(layer: Layer, rect: Rect, fill, line: rl.Color){
    command: DrawCommand = DrawRect {rect, fill, line }
    append(&state.draw_commands[layer], command)
}

draw_texture :: proc(layer: Layer,
    type: TextureType,
    position: [2]f32,
    scale :[2]f32 = 1.0,
    rotation: f32 = 0,
    frame: int = 0){
    command: DrawCommand = DrawTexture {position, type, frame, scale, rotation}
    append(&state.draw_commands[layer], command)
}

draw_text :: proc(layer: Layer, text: string, rect: Rect, color: rl.Color, font: rl.Font = {}, scale :f32 = 1, flags := bit_set[TextFlag]{.Centre}, display_length: int = 0){
    text := text
    if .NoClone not_in flags {
        text = strings.clone(text, context.temp_allocator)
    }
    command: DrawCommand = DrawText {
        text, rect, color, font, scale, flags, display_length
    }
    append(&state.draw_commands[layer], command)
}

render :: proc(commands: ^[Layer][dynamic]DrawCommand, ui : = false){
    rl.BeginShaderMode(state.shaders[.SDF].shader)
    defer rl.EndShaderMode()

    for &layer_commands, layer in commands {
        if layer == .UI && !ui do continue
        if layer != .UI && ui do continue
        for &command in layer_commands {
            switch &v in command {
            case Clip:
                if v.begin do rl.BeginScissorMode(i32(v.rect.x), i32(v.rect.y), i32(v.rect.z), i32(v.rect.w))
                else do rl.EndScissorMode()
            case DrawText:
                font := v.font
                if font == {} do font = state.default_font
                position := v.rect.xy
                if .Centre in v.flags {
                    text_size := measure_text(v.text, font) * v.scale
                    position += (v.rect.zw - text_size.xy) / 2
                }
                else if .Wrap in v.flags {
                    ui_draw_textblock(v.text, v.rect, v.color, font, true, v.display_length, v.scale)
                    break
                }
                draw_text_ex(font, v.text, position, f32(1), v.color, scale = v.scale)

            case DrawCircle:
                rl.DrawCircleV(v.circle.centre, v.circle.radius * v.scale, v.fill)
            case DrawLine:
                from, to := v.line.x, v.line.y

                displacement := to - from
                distance := linalg.length(displacement)
                direction := displacement / distance

                if v.rounded {
                    to -= direction * v.thickness
                    from += direction * v.thickness
                    distance -= v.thickness * 2

                    rl.DrawCircleV(from, v.thickness, v.color)
                    rl.DrawCircleV(to, v.thickness, v.color)
                }

                angle := linalg.to_degrees(linalg.atan2(direction.y, direction.x))
                start := from
                start -= [2]f32 { -direction.y, direction.x } * v.thickness
                rectangle := rl.Rectangle { start.x, start.y, distance, v.thickness * 2 }
                rl.DrawRectanglePro(rectangle, 0, angle, v.color)


            case DrawRect:
                rl.DrawRectangleRec(transmute(rl.Rectangle)v.rect, v.fill)
            case DrawTexture:
                texture :=  state.textures[v.type]
                frames :=   state.frames[v.type]
                cel_size := [2]f32 { f32((int(texture.width) / frames) + 1), f32(texture.height) }

                sign :=  linalg.sign(v.scale)

                src := rl.Rectangle { cel_size.x * f32(v.frame), 0, cel_size.x * sign.x, cel_size.y * sign.y }
                dst := rl.Rectangle { v.position.x, v.position.y, cel_size.x * v.scale.x, cel_size.y * v.scale.y }

                rotation := math.to_degrees(v.rotation)

                rl.DrawTexturePro(texture, src, dst, cel_size / 2, rotation, rl.WHITE)
            }
        }
        clear(&layer_commands)
    }
}