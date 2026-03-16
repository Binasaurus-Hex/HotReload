package game

Id :: u32

get_id         :: proc{get_id_string, get_id_bytes, get_id_rawptr, get_id_uintptr}
get_id_string  :: #force_inline proc(str: string)             -> Id { return get_id_bytes(transmute([]byte) str) }
get_id_rawptr  :: #force_inline proc(data: rawptr, size: int) -> Id { return get_id_bytes(([^]u8)(data)[:size])  }
get_id_uintptr :: #force_inline proc(ptr: uintptr) -> Id {
	ptr := ptr
	return get_id_bytes(([^]u8)(&ptr)[:size_of(ptr)])
}
get_id_bytes   :: proc(bytes: []byte) -> Id {
	/* 32bit fnv-1a hash */
	HASH_INITIAL :: 2166136261
	hash :: proc(hash: ^Id, data: []byte) {
		size := len(data)
		cptr := ([^]u8)(raw_data(data))
		for ; size > 0; size -= 1 {
			hash^ = Id(u32(hash^) ~ u32(cptr[0])) * 16777619
			cptr = cptr[1:]
		}
	}

	ui := &state.ui_state

	idx := ui.id_stack.idx
	res := ui.id_stack.items[idx - 1] if idx > 0 else HASH_INITIAL
	hash(&res, bytes)
	return res
}

push_id         :: proc{push_id_string, push_id_bytes, push_id_rawptr, push_id_uintptr}
push_id_string  :: #force_inline proc(str: string)              { push(&state.ui_state.id_stack, get_id(str))        }
push_id_rawptr  :: #force_inline proc(data: rawptr, size: int)  { push(&state.ui_state.id_stack, get_id(data, size)) }
push_id_uintptr :: #force_inline proc(ptr: uintptr)             { push(&state.ui_state.id_stack, get_id(ptr))        }
push_id_bytes   :: #force_inline proc(bytes: []byte)            { push(&state.ui_state.id_stack, get_id(bytes))      }

pop_id :: proc() {
	pop(&state.ui_state.id_stack)
}

Stack :: struct($T: typeid, $N: int) {
	idx:   i32,
	items: [N]T,
}

push :: #force_inline proc(stk: ^$T/Stack($V,$N), val: V) {
	if stk.idx >= len(stk.items) do return
	stk.items[stk.idx] = val
	stk.idx += 1
}
pop  :: #force_inline proc(stk: ^$T/Stack($V,$N)) -> (popped: bool) {
    if stk.idx <= 0 do return false
	stk.idx -= 1
	return true
}

top_safe :: #force_inline proc(stk: ^$T/Stack($V, $N)) -> (val: V, ok: bool){
    if stk.idx <= 0 do return {}, false
    return stk.items[stk.idx - 1], true
}
