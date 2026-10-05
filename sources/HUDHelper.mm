//
//  HUDHelper.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <cstdint>
#import <spawn.h>
#import <notify.h>
#import <sys/wait.h>
#import <errno.h>
#import "rootless.h"
#import <mach-o/dyld.h>

#import "HUDHelper.h"

extern "C" char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern "C" int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern "C" int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern "C" int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

BOOL IsHUDEnabled(void)
{
    NSString *pidString = [NSString stringWithContentsOfFile:ROOT_PATH_NS(PID_PATH)
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];

    if (pidString && [pidString length] > 0)
    {
        pid_t pid = (pid_t)[pidString intValue];
        if (pid <= 0) return NO;
        
        errno = 0;
        int res = kill(pid, 0);
        if (res == 0 || errno == EPERM) {
            return YES;
        }
        
        // Process is dead (ESRCH)
        unlink([ROOT_PATH_NS(PID_PATH) UTF8String]);
        return NO;
    }
    return NO;
}

void SetHUDEnabled(BOOL isEnabled)
{
    NSLog(@"[ESP_LOG] [HUD_CTRL] >>> SetHUDEnabled called with isEnabled: %d", (int)isEnabled);
    
    // Always terminate any running instance first
    NSString *pidString = [NSString stringWithContentsOfFile:ROOT_PATH_NS(PID_PATH)
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    if (pidString && [pidString length] > 0)
    {
        pid_t pid = (pid_t)[pidString intValue];
        if (pid > 0) {
            NSLog(@"[ESP_LOG] [HUD_CTRL] Terminating old HUD process PID: %d", (int)pid);
            kill(pid, SIGTERM);
            kill(pid, SIGKILL);
            
            // Also invoke kill -9 via persona 99
            posix_spawnattr_t killAttr;
            posix_spawnattr_init(&killAttr);
            posix_spawnattr_set_persona_np(&killAttr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
            posix_spawnattr_set_persona_uid_np(&killAttr, 0);
            posix_spawnattr_set_persona_gid_np(&killAttr, 0);
            
            char pidArg[32];
            snprintf(pidArg, sizeof(pidArg), "%d", (int)pid);
            const char *killArgs[] = { "/bin/kill", "-9", pidArg, NULL };
            pid_t kpid = 0;
            posix_spawn(&kpid, "/bin/kill", NULL, &killAttr, (char **)killArgs, environ);
            if (kpid > 0) {
                int status;
                waitpid(kpid, &status, 0);
            }
            posix_spawnattr_destroy(&killAttr);
        }
        unlink([ROOT_PATH_NS(PID_PATH) UTF8String]);
    }
    
    notify_post(NOTIFY_DESTROY_HUD);

    if (isEnabled)
    {
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);

        posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
        posix_spawnattr_set_persona_uid_np(&attr, 0);
        posix_spawnattr_set_persona_gid_np(&attr, 0);
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);

        char executablePath[1024] = {0};
        uint32_t executablePathSize = sizeof(executablePath);
        _NSGetExecutablePath(executablePath, &executablePathSize);

        pid_t task_pid = 0;
        const char *args[] = { executablePath, "-hud", NULL };
        int ret = posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        posix_spawnattr_destroy(&attr);

        NSLog(@"[ESP_LOG] [HUD_CTRL] posix_spawn spawned HUD process -> ret:%d | task_pid:%d | execPath:%s",
              ret, (int)task_pid, executablePath);
    }
}

