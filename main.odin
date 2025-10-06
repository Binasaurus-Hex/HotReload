package main

import "core:fmt"
import "core:dynlib"
import "core:os"
import "core:os/os2"
import rl "vendor:raylib"

GameAPI :: struct {
    init_window: proc(),
    run: proc() -> bool,
    save: proc() -> []u8,
    load: proc(state: []u8),

    _game_api_handle: dynlib.Library
}

get_api_path :: proc(version: int) -> string {
    return fmt.tprintf("game_{}.dll", version)
}

build_api :: proc(version: int) -> (path: string, success: bool) {

    path = get_api_path(version)
    output := fmt.tprint("-out=", path)
    process_description := os2.Process_Desc {
        command = {
            "odin",
            "build",
            "game",
            "-build-mode=dll",
            "-define:RAYLIB_SHARED=true",
            "-extra-linker-flags=/NOEXP /NOIMPLIB",
            output
            }
    }
    process, err := os2.process_start(process_description)
    assert(err == nil)
    state, wait_err := os2.process_wait(process)
    assert(wait_err == nil)
    return path, state.exit_code == 0
}

main :: proc(){

    apis: [dynamic]GameAPI
    api_version: int
    started: bool
    state: []u8
    api: GameAPI

    for {

        if dll_path, success := build_api(api_version); success {
            api = {}
            count, ok := dynlib.initialize_symbols(&api, dll_path, "", "_game_api_handle")
            append(&apis, api)
            api_version += 1
        }
        else if !started {
            break
        }


        if started {
            api.load(state)
        }

        if !started {
            api.init_window()
            started = true
        }


        reload := api.run()

        if reload do state = api.save()

        // dynlib.unload_library(api._game_api_handle)


        free_all(context.temp_allocator)

        if !reload do break
    }

    for api, i in apis {
		if !dynlib.unload_library(api._game_api_handle) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}

        dll := fmt.tprintf("game_{}.dll", i)
        err: os2.Error
        err = os2.remove(dll)
        assert(err == nil, fmt.tprint(err, "| ", dll))
    }
}