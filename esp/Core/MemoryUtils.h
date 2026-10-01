#ifndef MEMORY_UTILS_H
#define MEMORY_UTILS_H

#include <mach/mach.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>

class MemoryUtils {
public:
    static pid_t get_pid_for_process(const char *process_name);
    static mach_port_t get_task_for_pid(pid_t pid);
    static uintptr_t get_module_base(mach_port_t task, const char *module_name);
    
    template <typename T>
    static T read(mach_port_t task, uintptr_t address) {
        T data{};
        if (!task || !address) return data;
        vm_size_t size = sizeof(T);
        vm_read_overwrite(task, (vm_address_t)address, size, (vm_address_t)&data, &size);
        return data;
    }

    static bool read_raw(mach_port_t task, uintptr_t address, void *buffer, size_t size) {
        if (!task || !address || !buffer) return false;
        vm_size_t read_size = size;
        kern_return_t kr = vm_read_overwrite(task, (vm_address_t)address, read_size, (vm_address_t)buffer, &read_size);
        return kr == KERN_SUCCESS;
    }
};

#endif // MEMORY_UTILS_H
