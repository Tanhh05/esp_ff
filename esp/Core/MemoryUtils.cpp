#include "MemoryUtils.h"
#include <sys/sysctl.h>
#include <mach-o/dyld_images.h>
#include <cstring>
#include <cstdlib>

pid_t MemoryUtils::get_pid_for_process(const char *process_name) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) return 0;

    struct kinfo_proc *proc_list = (struct kinfo_proc *)malloc(size);
    if (!proc_list) return 0;

    if (sysctl(mib, 4, proc_list, &size, NULL, 0) < 0) {
        free(proc_list);
        return 0;
    }

    int proc_count = (int)(size / sizeof(struct kinfo_proc));
    pid_t result_pid = 0;

    for (int i = 0; i < proc_count; i++) {
        if (strstr(proc_list[i].kp_proc.p_comm, process_name) != NULL) {
            result_pid = proc_list[i].kp_proc.p_pid;
            break;
        }
    }

    free(proc_list);
    return result_pid;
}

mach_port_t MemoryUtils::get_task_for_pid(pid_t pid) {
    mach_port_t task = 0;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        return 0;
    }
    return task;
}

uintptr_t MemoryUtils::get_module_base(mach_port_t task, const char *module_name) {
    task_dyld_info_data_t dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (kr != KERN_SUCCESS) return 0;

    struct dyld_all_image_infos infos;
    vm_size_t read_size = sizeof(infos);
    kr = vm_read_overwrite(task, dyld_info.all_image_info_addr, read_size, (vm_address_t)&infos, &read_size);
    if (kr != KERN_SUCCESS) return 0;

    struct dyld_image_info *image_array = (struct dyld_image_info *)malloc(sizeof(struct dyld_image_info) * infos.infoArrayCount);
    read_size = sizeof(struct dyld_image_info) * infos.infoArrayCount;
    kr = vm_read_overwrite(task, (vm_address_t)infos.infoArray, read_size, (vm_address_t)image_array, &read_size);
    if (kr != KERN_SUCCESS) {
        free(image_array);
        return 0;
    }

    uintptr_t base_address = 0;
    for (uint32_t i = 0; i < infos.infoArrayCount; i++) {
        char path_buffer[1024] = {0};
        read_size = sizeof(path_buffer);
        vm_read_overwrite(task, (vm_address_t)image_array[i].imageFilePath, read_size, (vm_address_t)path_buffer, &read_size);

        if (strstr(path_buffer, module_name) != NULL) {
            base_address = (uintptr_t)image_array[i].imageLoadAddress;
            break;
        }
    }

    free(image_array);
    return base_address;
}
