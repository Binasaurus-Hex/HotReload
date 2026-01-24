package game

import "core:sync"
import "core:thread"
import "core:slice"
import "core:time"
import "core:mem/virtual"
import os "core:os/os2"

Directory :: struct {
    arena: virtual.Arena,
    files: []os.File_Info,
}

Checker :: struct {
    thread: ^thread.Thread,
    mutex: sync.Mutex,
    on: bool,
    directories: map[string]Directory
}

@private
checker: Checker

@private
directory_checker :: proc(){

    for checker.on {
        if sync.guard(&checker.mutex){
            for path, &directory in checker.directories {
                allocator := virtual.arena_allocator(&directory.arena)
                free_all(allocator)
                new_files := os.read_all_directory_by_path(path, allocator) or_continue
                directory.files = new_files
            }
        }

        time.sleep(2 * time.Millisecond)
    }
}

start_file_checker :: proc(){
    checker.on = true
    checker.thread = thread.create_and_start(directory_checker)
}

stop_file_checker :: proc(){
    checker.on = false
    thread.join(checker.thread)
}

clone_file_infos :: proc(infos: []os.File_Info, allocator := context.temp_allocator) -> (cloned: []os.File_Info) {
    cloned = slice.clone(infos, allocator)
    for &clone in cloned {
        clone = os.file_info_clone(clone, allocator) or_continue
    }
    return
}

read_all_directory_cached :: proc(path: string, allocator := context.temp_allocator) -> []os.File_Info {

    if sync.guard(&checker.mutex){
        if directory, found := checker.directories[path]; found {
            return clone_file_infos(directory.files, allocator)
        }

        directory: Directory
        allocation_err := virtual.arena_init_growing(&directory.arena)
        assert(allocation_err == nil)
        checker.directories[path] = directory
    }
    return {}
}