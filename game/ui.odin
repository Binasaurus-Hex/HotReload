package game

import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

Rect :: distinct [4]f32

draw_text_ex :: proc(font: rl.Font, text: string, position: [2]f32, spacing: f32, tint: rl.Color, draw := true, scale: f32 = 1) -> f32 {
    scale := scale / 2
    offset : [2]f32

    for c, _ in text {
        index := rl.GetGlyphIndex(font, c)

        if c == '\n' || c == '\r' do continue
        if c != ' ' && c != '\t' && draw {
            rl.DrawTextCodepoint(font, c, position + offset, f32(font.baseSize) * scale, tint)
        }

        if font.glyphs[index].advanceX == 0 {
            offset.x += f32(font.recs[index].width) * scale + spacing
        }
        else {
            offset.x += f32(font.glyphs[index].advanceX) * scale + spacing
        }
    }
    return offset.x
}

ui_draw_text :: proc(text: string, position: [2]f32, color: rl.Color, font: rl.Font){
    draw_text_ex(font, text, position, f32(1), color)
}

ui_draw_textblock :: proc(text:string, rect: Rect, color: rl.Color, font: rl.Font, mask_length: bool = false, display_length: int = 0, scale :f32 = 1){

    text := text
    rect := rect

    start_len := len(text)

    for len(text) > 0 {
        r := eat_top_rect_ref(&rect, f32(font.baseSize) * scale / 2, 0)
        last_space: int
        base: int = start_len - len(text)
        at_end: bool
        for ch, i in text {
            if ch == ' ' {
                last_space = i
            }

            if ch == '\n' {
                last_space = i
                break
            }

            size := measure_text(text[:i + 1], font) * scale
            if size.x > r.z {
                break
            }
            at_end = i == len(text) - 1
        }
        if at_end do last_space = len(text) - 1

        if mask_length && (last_space >= display_length - base) {
            draw_text_ex(font, text[:display_length - base], r.xy, f32(1), color, scale = scale)
            return
        }
        else {
            draw_text_ex(font, text[:last_space + 1], r.xy, f32(1), color, scale = scale)
        }
        text = text[last_space + 1:]
    }
}

grid_next_rect :: proc(grid_line, grid: ^Rect, width: f32, line_height: f32, spacing :f32 = 20) -> Rect {

    if grid_line.z < width {
        new_line := eat_top_rect_ref(grid, line_height, spacing)
        grid_line ^= new_line
    }

    rect, remainder := eat_left_rect(grid_line^, width, spacing)
    grid_line ^= remainder
    return rect
}

fullscreen_rect :: proc() -> Rect {
    return { 0, 0, f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
}

rect_centre :: proc(rect: Rect) -> [2]f32 {
    return rect.xy + (rect.zw / 2.)
}

centre_rect :: proc(rect: Rect) -> Rect {
    rect := rect
    rect.xy = rect_centre(rect)
    rect.zw = { 0, 0 }
    return rect
}

pad_rect :: proc(rect: Rect, padding: [2]f32) -> Rect {
    rect := rect
    rect.xy += padding
    rect.zw -= padding * 2
    return rect
}

eat_top_rect_ref :: proc(rect: ^Rect, x:f32, spacing: f32) -> Rect {
    eaten, remainder := eat_top_rect(rect^, x, spacing)
    rect ^= remainder
    return eaten
}

eat_left_rect_ref :: proc(rect: ^Rect, x: f32, spacing: f32) -> Rect {
    eaten, remainder := eat_left_rect(rect^, x, spacing)
    rect ^= remainder
    return eaten
}

eat_left_rect :: proc(rect: Rect, x: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    eaten = {rect.x, rect.y, x, rect.w }
    remainder = rect
    remainder.x += x + spacing
    remainder.z -= x + spacing
    return
}

eat_top_rect :: proc(rect: Rect, y: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    eaten = {rect.x, rect.y, rect.z, y }
    remainder = rect
    remainder.y += y + spacing
    remainder.w -= y + spacing
    return
}

eat_bottom_rect :: proc(rect: Rect, y: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    remainder = rect
    remainder.w -= (y + spacing)
    eaten = { rect.x, rect.y + rect.w - y, rect.z, y }
    return
}

eat_bottom_rect_ref :: proc(rect: ^Rect, y: f32, spacing: f32) -> Rect {
    eaten, remainder := eat_bottom_rect(rect^, y, spacing)
    rect ^= remainder
    return eaten
}

eat_right_rect :: proc(rect: Rect, x: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    remainder = rect
    remainder.z -= (x + spacing)
    eaten = { rect.x + rect.z - x, rect.y, x, rect.w }
    return
}

eat_right_rect_ref :: proc(rect: ^Rect, x: f32, spacing: f32) -> Rect {
    eaten, remainder := eat_right_rect(rect^, x, spacing)
    rect ^= remainder
    return eaten
}

measure_text :: proc(text: string, font: rl.Font) -> [2]f32 {
    width := draw_text_ex(font, text, {}, f32(1), {}, draw = false)
    return { width, f32(font.baseSize) / 2}
}

rect_overlaps :: proc(r1, r2: Rect) -> bool {
    intersection := rect_intersection(r1, r2)
    return intersection.z != 0 && intersection.w != 0
}

rect_intersection :: proc(r1, r2: Rect) -> Rect {
	x1 := max(r1.x, r2.x)
	y1 := max(r1.y, r2.y)
	x2 := min(r1.x + r1.z, r2.x + r2.z)
	y2 := min(r1.y + r1.w, r2.y + r2.w)
	if x2 < x1 { x2 = x1 }
	if y2 < y1 { y2 = y1 }
	return Rect{x1, y1, x2 - x1, y2 - y1}
}

scale_line :: proc(line: [2][2]f32, scale: f32) -> [2][2]f32 {
    dir := line.y - line.x
    return { line.x, line.x + dir * scale }
}


// UI, buttons and such

HSVA :: [4]f32

color_to_hsva :: proc(color: rl.Color) -> HSVA {
    hsva: HSVA
    hsva.xyz = rl.ColorToHSV(color)
    hsva.w = f32(color.a) / 255.
    return hsva
}
color_from_hsva :: proc(hsva: HSVA) -> rl.Color {
    color := rl.ColorFromHSV(hsva.x, hsva.y, hsva.z)
    color.a = u8(hsva.a * 255)
    return color
}

UIState :: struct {
    clip_rect: Rect,
    id_stack: Stack(Id, 32),
    string_length: map[Id]f32,
    rects: map[Id]Rect,
    colors: map[Id]HSVA,
    scale: map[Id]f32,
    shadow_start: int,
}

interpolate_scale :: proc(s: f32, id: Id, delta: f32, reset: bool) -> f32 {
    ui := &state.ui_state
    current := ui.scale[id] if !reset else {}
    current = damp(current, s, f32(20), delta)
    ui.scale[id] = current
    return current
}

interpolate_rect :: proc(r: Rect, id: Id, delta: f32, reset: bool, default: Rect = {}, speed: f32 = 20) -> Rect {
    ui := &state.ui_state
    target := r
    current, found := ui.rects[id]
    if !found || reset {
        current = default
    }
    current = damp(current, target, speed, delta)
    ui.rects[id] = current
    return current
}

degrees_to_direction :: proc(degrees: f32) -> [2]f32 {
    radians := linalg.to_radians(degrees)
    return { linalg.cos(radians), linalg.sin(radians) }
}

direction_to_degrees :: proc(direction: [2]f32) -> f32 {
    return linalg.to_degrees(2 * linalg.PI + linalg.atan2(direction.y, direction.x))
}

interpolate_angle :: proc(from, to: f32, speed: f32, delta: f32) -> f32 {
    from := degrees_to_direction(from)
    to := degrees_to_direction(to)
    interpolated_direction := linalg.normalize0(damp(from, to, speed, delta))
    return direction_to_degrees(interpolated_direction)
}

draw_color :: proc(color: HSVA){
    rect := Rect { 100, 100, 200, 100 }
    for component in color {
        slot := eat_left_rect_ref(&rect, 50, 10)
        draw_text(.UI, fmt.tprintf("%.1f", component), slot, rl.RED)
    }
}



interpolate_color_hsva :: proc(color: rl.Color, id: Id, delta: f32, reset: bool, speed: f32 = 10) -> rl.Color {
    ui := &state.ui_state
    target := color_to_hsva(color)
    current := ui.colors[id] if !reset else {}
    hue := current.x
    current = damp(current, target, speed, delta)
    current.x = interpolate_angle(hue, target.x, speed * 2, delta)
    ui.colors[id] = current
    return color_from_hsva(current)
}

interpolate_color :: proc(color: rl.Color, id: Id, delta: f32, reset: bool, speed :f32 = 3) -> rl.Color {
    ui := &state.ui_state
    target := rl.ColorNormalize(color)
    current := ui.colors[id] if !reset else {}

    current = damp(current, target, speed, delta)
    ui.colors[id] = current
    return rl.ColorFromNormalized(current)
}

animate_string :: proc(s: string, speed: f32, delta: f32, reset := false, id := Id(0)) -> string {
    ui := &state.ui_state
    id := get_id(s) if id == {} else id
    target_len := f32(len(s))
    current_len := ui.string_length[id] if !reset else 0
    current_len += speed * delta
    current_len = clamp(current_len, 0, target_len)
    ui.string_length[id] = current_len
    return s[:int(current_len)]
}
