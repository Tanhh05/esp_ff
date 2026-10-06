#include "GameLogic.h"
#include "MemoryUtils.h"
#include "offsets_1.132.1.h"
#import <Foundation/Foundation.h>
#import "../drawing_view/esp.h"
#include <iostream>
#include <map>
#include <vector>

bool GameLogic::initialize() {
    const char *proc_names[] = {"freefire", "FreeFire", "freefireth", "FreeFireTH", "Free Fire", "dtsg", NULL};
    gamePid = 0;
    for (int i = 0; proc_names[i] != NULL; i++) {
        gamePid = MemoryUtils::get_pid_for_process(proc_names[i]);
        if (gamePid > 0) {
            NSLog(@"[ESP_LOG] Found Game PID: %d for process: %s", gamePid, proc_names[i]);
            break;
        }
    }
    if (!gamePid) {
        statusMsg = "Error: Game process not found";
        NSLog(@"[ESP_LOG] Error: No Free Fire process found in kernel scan!");
        return false;
    }

    gameTask = MemoryUtils::get_task_for_pid(gamePid);
    if (!gameTask) {
        statusMsg = "Error: task_for_pid failed (Entitlements issue)";
        NSLog(@"[ESP_LOG] Error: task_for_pid failed for PID %d! Check entitlements!", gamePid);
        return false;
    }
    NSLog(@"[ESP_LOG] Successfully got task port: %u for PID: %d", gameTask, gamePid);

    unityFrameworkBase = MemoryUtils::get_module_base(gameTask, "UnityFramework");
    if (!unityFrameworkBase) {
        statusMsg = "Error: UnityFramework base address not found";
        NSLog(@"[ESP_LOG] Error: Failed to find UnityFramework base address in PID %d", gamePid);
        return false;
    }
    NSLog(@"[ESP_LOG] UnityFramework Base Address: 0x%llx", (unsigned long long)unityFrameworkBase);

    statusMsg = "Success: Attached to Game & UnityFramework";
    return true;
}

std::string GameLogic::readIl2CppString(uintptr_t stringPtr) {
    if (!stringPtr || !gameTask) return "";
    int32_t length = MemoryUtils::read<int32_t>(gameTask, stringPtr + 0x10);
    if (length <= 0 || length > 64) return "";

    char16_t buffer[64] = {0};
    if (!MemoryUtils::read_raw(gameTask, stringPtr + Offsets::SystemString_Chars, buffer, length * sizeof(char16_t))) {
        return "";
    }

    std::string result = "";
    for (int i = 0; i < length; i++) {
        result += (char)buffer[i];
    }
    return result;
}

// Helper to strip PAC (Pointer Authentication Code) bits on iOS ARM64
static inline uintptr_t StripPAC(uintptr_t ptr) {
    if (!ptr) return 0;
    // Clear top 16 bits used by PAC signatures on iOS ARM64/ARM64e
    return ptr & 0x0000007FFFFFFFFFULL;
}

void GameLogic::updateData(float screenWidth, float screenHeight) {
    if (!gameTask && !initialize()) return;
    std::vector<PlayerData> newPlayers;

    // 1. GameFacade_TypeInfo (0xBB46A50)
    uintptr_t typeInfo = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, unityFrameworkBase + Offsets::GameFacade_TypeInfo));
    if (!typeInfo) {
        std::lock_guard<std::mutex> lock(dataMutex);
        statusMsg = "Error: Null GameFacade_TypeInfo";
        players.clear();
        return;
    }

    // 2. StaticFields (TypeInfo + 0xB8)
    uintptr_t staticFields = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, typeInfo + Offsets::GameFacade_StaticFields));
    if (!staticFields) {
        std::lock_guard<std::mutex> lock(dataMutex);
        statusMsg = "Error: Null StaticFields (TypeInfo + 0xB8)";
        players.clear();
        static int sfLog = 0;
        if (++sfLog % 60 == 0) {
            NSLog(@"[ESP_LOG] [WAIT] TI:0x%llx | SF:0x0 (Waiting for GameFacade static fields)", (unsigned long long)typeInfo);
        }
        return;
    }

    // 3. CurrentMatchGame (StaticFields + 0x8)
    uintptr_t matchGame = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, staticFields + Offsets::CurrentMatchGame));
    static int logThrottle = 0;
    if (++logThrottle % 60 == 0) {
        NSLog(@"[ESP_LOG] [CHAIN] Base:0x%llx | TI:0x%llx | SF:0x%llx | MG:0x%llx",
              (unsigned long long)unityFrameworkBase,
              (unsigned long long)typeInfo,
              (unsigned long long)staticFields,
              (unsigned long long)matchGame);
    }
    if (!matchGame) {
        statusMsg = "Status: In Lobby / Null MatchGame (SF + 0x8)";
        return;
    }

    // 4. CameraControllerManager (MatchGame + 0xD8) & MainCamera (0x20) & ViewMatrix (0x10 -> 0xD8)
    uintptr_t cameraMgr = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, matchGame + Offsets::MatchGame_CameraControllerManager));
    uintptr_t camera = cameraMgr ? StripPAC(MemoryUtils::read<uintptr_t>(gameTask, cameraMgr + Offsets::CameraControllerManager_Camera)) : 0;
    uintptr_t viewMatrixPtr = camera ? StripPAC(MemoryUtils::read<uintptr_t>(gameTask, camera + Offsets::Camera_ViewMatrix)) : 0;

    // 5. Match (MatchGame + 0x90)
    uintptr_t match = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, matchGame + Offsets::MatchGame_m_Match));

    // 6. LocalPlayer (Match + 0xD8)
    uintptr_t localPlayer = match ? StripPAC(MemoryUtils::read<uintptr_t>(gameTask, match + Offsets::Match_LocalPlayer)) : 0;

    // 7. PlayerList (Match + 0x158) & PlayerDict (0x128)
    uintptr_t playerListPtr = match ? StripPAC(MemoryUtils::read<uintptr_t>(gameTask, match + Offsets::Match_PlayerList_List)) : 0;
    uintptr_t playerDictPtr = match ? StripPAC(MemoryUtils::read<uintptr_t>(gameTask, match + Offsets::Match_PlayerDict)) : 0;

    std::vector<uintptr_t> playerPointers;

    // 1. Try Dictionary (Match + 0x128)
    int32_t dictCount = 0;
    if (playerDictPtr) {
        uintptr_t entries = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, playerDictPtr + 0x18));
        dictCount = MemoryUtils::read<int32_t>(gameTask, playerDictPtr + 0x20);
        if (entries && dictCount > 0 && dictCount <= 100) {
            for (int i = 0; i < dictCount; i++) {
                uintptr_t player = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, entries + 0x40 + (i * 0x28)));
                if (player && player != localPlayer) {
                    playerPointers.push_back(player);
                }
            }
        }
    }

    // 2. Try List (Match + 0x158)
    int32_t listCount = 0;
    if (playerPointers.empty() && playerListPtr) {
        uintptr_t items = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, playerListPtr + Offsets::Il2CppList_Items));
        listCount = MemoryUtils::read<int32_t>(gameTask, playerListPtr + Offsets::Il2CppList_Count);
        if (items && listCount > 0 && listCount <= 100) {
            for (int i = 0; i < listCount; i++) {
                uintptr_t player = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, items + 0x20 + (i * 8)));
                if (player && player != localPlayer) {
                    playerPointers.push_back(player);
                }
            }
        }
    }

    static int detailThrottle = 0;
    if (++detailThrottle % 60 == 0) {
        NSLog(@"[ESP_LOG] [DETAILS] CamMgr:0x%llx | Cam:0x%llx | VM:0x%llx | Match:0x%llx | Local:0x%llx | PlList:0x%llx (cnt:%d) | Dict:0x%llx (cnt:%d) | Found:%zu",
              (unsigned long long)cameraMgr,
              (unsigned long long)camera,
              (unsigned long long)viewMatrixPtr,
              (unsigned long long)match,
              (unsigned long long)localPlayer,
              (unsigned long long)playerListPtr,
              listCount,
              (unsigned long long)playerDictPtr,
              dictCount,
              playerPointers.size());
    }

    if (!match) {
        statusMsg = "Status: In Lobby / Null Match (MG + 0x90)";
        return;
    }

    if (!cameraMgr || !camera || !viewMatrixPtr) {
        statusMsg = "Status: Waiting for In-Game Camera";
        return;
    }

    Matrix4x4 viewMatrix = MemoryUtils::read<Matrix4x4>(gameTask, viewMatrixPtr + Offsets::Camera_ViewMatrix_Array);
    if (viewMatrix.m[0] == 0.0f && viewMatrix.m[1] == 0.0f && viewMatrix.m[2] == 0.0f && viewMatrix.m[3] == 0.0f) {
        viewMatrix = MemoryUtils::read<Matrix4x4>(gameTask, viewMatrixPtr + Offsets::Camera_ViewMatrix_Array + 0x10);
    }

    static int vmatThrottle = 0;
    if (++vmatThrottle % 60 == 0) {
        NSLog(@"[ESP_LOG] [VMAT] [%.3f, %.3f, %.3f, %.3f] [%.3f, %.3f, %.3f, %.3f] [%.3f, %.3f, %.3f, %.3f] [%.3f, %.3f, %.3f, %.3f]",
              viewMatrix.m[0], viewMatrix.m[1], viewMatrix.m[2], viewMatrix.m[3],
              viewMatrix.m[4], viewMatrix.m[5], viewMatrix.m[6], viewMatrix.m[7],
              viewMatrix.m[8], viewMatrix.m[9], viewMatrix.m[10], viewMatrix.m[11],
              viewMatrix.m[12], viewMatrix.m[13], viewMatrix.m[14], viewMatrix.m[15]);
    }

    auto getPlayerTeamID = [](mach_port_t task, uintptr_t p) -> uint8_t {
        if (!p) return 255;
        // 1. Check inlined struct BEADLMGGGGL (0x408 + 0x08 = 0x410)
        uint8_t inlineTeam = MemoryUtils::read<uint8_t>(task, p + Offsets::Player_PlayerIDStruct + 0x08);
        if (inlineTeam > 0 && inlineTeam < 250) return inlineTeam;

        // 2. Check if 0x408 is an object pointer
        uintptr_t idStruct = StripPAC(MemoryUtils::read<uintptr_t>(task, p + Offsets::Player_PlayerIDStruct));
        if (idStruct > 0x100000000ULL && idStruct < 0x7FFFFFFFFFFFULL) {
            uint8_t ptrTeam = MemoryUtils::read<uint8_t>(task, idStruct + Offsets::BEADLMGGGGL_TeamID);
            if (ptrTeam > 0 && ptrTeam < 250) return ptrTeam;
        }

        // 3. Fallback direct 0x420
        uint8_t fbTeam = MemoryUtils::read<uint8_t>(task, p + Offsets::Player_PlayerIDStruct + Offsets::BEADLMGGGGL_TeamID);
        return fbTeam;
    };

    uint8_t localTeamID = 255;
    Vector3 localPos{0, 0, 0};

    if (localPlayer) {
        localTeamID = getPlayerTeamID(gameTask, localPlayer);
        uintptr_t localCamTF = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, localPlayer + Offsets::Player_MainCameraTransform));
        if (localCamTF) {
            localPos = UnityMath::GetTransformPosition(gameTask, localCamTF);
        }
    }
    this->cachedCameraMgr = cameraMgr;
    this->cachedLocalPos = localPos;



    if (playerPointers.empty()) {
        char buf[64];
        snprintf(buf, sizeof(buf), "Status: In Match (Dict:%d, List:%d)", dictCount, listCount);
        statusMsg = buf;
        return;
    }

    static int teamLogThrottle = 0;
    bool shouldLogTeam = (++teamLogThrottle % 60 == 0);

    for (uintptr_t player : playerPointers) {
        if (!player || player == localPlayer) continue;

        // Team ID Filter
        uint8_t teamID = getPlayerTeamID(gameTask, player);

        if (shouldLogTeam) {
            uint8_t localBytes[32] = {0};
            uint8_t enemyBytes[32] = {0};
            for (int b = 0; b < 32; b++) {
                localBytes[b] = MemoryUtils::read<uint8_t>(gameTask, localPlayer + 0x408 + b);
                enemyBytes[b] = MemoryUtils::read<uint8_t>(gameTask, player + 0x408 + b);
            }
            NSLog(@"[ESP_LOG] [HEX_LOCAL 0x408..0x427] %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x || %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x",
                  localBytes[0], localBytes[1], localBytes[2], localBytes[3],
                  localBytes[4], localBytes[5], localBytes[6], localBytes[7],
                  localBytes[8], localBytes[9], localBytes[10], localBytes[11],
                  localBytes[12], localBytes[13], localBytes[14], localBytes[15],
                  localBytes[16], localBytes[17], localBytes[18], localBytes[19],
                  localBytes[20], localBytes[21], localBytes[22], localBytes[23],
                  localBytes[24], localBytes[25], localBytes[26], localBytes[27],
                  localBytes[28], localBytes[29], localBytes[30], localBytes[31]);
            NSLog(@"[ESP_LOG] [HEX_ENEMY 0x408..0x427] %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x || %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x",
                  enemyBytes[0], enemyBytes[1], enemyBytes[2], enemyBytes[3],
                  enemyBytes[4], enemyBytes[5], enemyBytes[6], enemyBytes[7],
                  enemyBytes[8], enemyBytes[9], enemyBytes[10], enemyBytes[11],
                  enemyBytes[12], enemyBytes[13], enemyBytes[14], enemyBytes[15],
                  enemyBytes[16], enemyBytes[17], enemyBytes[18], enemyBytes[19],
                  enemyBytes[20], enemyBytes[21], enemyBytes[22], enemyBytes[23],
                  enemyBytes[24], enemyBytes[25], enemyBytes[26], enemyBytes[27],
                  enemyBytes[28], enemyBytes[29], enemyBytes[30], enemyBytes[31]);
        }

        // If localTeamID and player teamID match and are valid (> 0 && < 250), skip teammate
        if (localTeamID > 0 && localTeamID < 250 && teamID > 0 && teamID < 250 && localTeamID == teamID) {
            continue;
        }

        // Bones (Head 0x6A0 -> 0x10 & RightToe 0x6F0 -> 0x10)
        uintptr_t headNode = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, player + Offsets::Player_HeadNode));
        uintptr_t toeNode = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, player + Offsets::Player_RightToeNode));

        Vector3 headPos{0, 0, 0};
        Vector3 toePos{0, 0, 0};
        uintptr_t headTransform = 0;
        uintptr_t toeTransform = 0;
        bool hasBones = false;

        if (headNode && toeNode) {
            headTransform = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, headNode + Offsets::ITransformNode_Transform));
            toeTransform = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, toeNode + Offsets::ITransformNode_Transform));
            if (headTransform && toeTransform) {
                headPos = UnityMath::GetTransformPosition(gameTask, headTransform);
                toePos = UnityMath::GetTransformPosition(gameTask, toeTransform);
                if (headPos.x != 0 || headPos.y != 0 || headPos.z != 0) {
                    hasBones = true;
                }
            }
        }

        if (!hasBones) {
            uintptr_t rootTF = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, player + Offsets::Player_MainCameraTransform));
            if (rootTF) {
                Vector3 rootPos = UnityMath::GetTransformPosition(gameTask, rootTF);
                if (rootPos.x != 0 || rootPos.y != 0 || rootPos.z != 0) {
                    headPos = Vector3{rootPos.x, rootPos.y + 0.85f, rootPos.z};
                    toePos = Vector3{rootPos.x, rootPos.y - 0.90f, rootPos.z};
                    hasBones = true;
                }
            }
        }

        if (!hasBones) continue;

        // Auto height calibration: If toe bone is missing or LOD flattened at long distance (<1.0m difference)
        float boneDist = fabsf(headPos.y - toePos.y);
        if (boneDist < 0.8f || boneDist > 2.6f) {
            toePos = Vector3{headPos.x, headPos.y - 1.75f, headPos.z};
        }

        Vector2 headScreen, toeScreen;
        bool headVis = UnityMath::WorldToScreen(headPos, viewMatrix, screenWidth, screenHeight, headScreen);
        bool toeVis = UnityMath::WorldToScreen(toePos, viewMatrix, screenWidth, screenHeight, toeScreen);

        static int playerDebugThrottle = 0;
        if (++playerDebugThrottle % 30 == 0) {
            float w = viewMatrix.m[3] * headPos.x + viewMatrix.m[7] * headPos.y + viewMatrix.m[11] * headPos.z + viewMatrix.m[15];
            float clipX = viewMatrix.m[0] * headPos.x + viewMatrix.m[4] * headPos.y + viewMatrix.m[8] * headPos.z + viewMatrix.m[12];
            float clipY = viewMatrix.m[1] * headPos.x + viewMatrix.m[5] * headPos.y + viewMatrix.m[9] * headPos.z + viewMatrix.m[13];
            NSLog(@"[ESP_LOG] [PLAYER_DBG] localTeam:%d | enemyTeam:%d | head:(%.1f, %.1f, %.1f) | vis:%d,%d | headScr:(%.1f, %.1f) | w:%.2f | clip:(%.1f, %.1f) | scr:(%.0f, %.0f)",
                  localTeamID, teamID, headPos.x, headPos.y, headPos.z, (int)headVis, (int)toeVis, headScreen.x, headScreen.y, w, clipX, clipY, screenWidth, screenHeight);
        }

        if (!headVis && !toeVis) continue;
        if (!headVis) {
            headScreen = Vector2{toeScreen.x, toeScreen.y - 60.0f};
        } else if (!toeVis) {
            toeScreen = Vector2{headScreen.x, headScreen.y + 80.0f};
        }

        float dist = headPos.Distance(localPos);
        if (dist > 350.0f) continue;

        // Multi-Path Health (HP) Reader & Real-Time RAM Scanner
        int curHP = 200, maxHP = 200;
        bool hpFound = false;

        // Path 1: PRIDataPool Property Objects Scan (+0x10, +0x20 arrays of pointers)
        for (uint64_t priOff : {0x70ULL, 0x68ULL, 0x78ULL, 0x80ULL}) {
            uintptr_t priDataPool = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, player + priOff));
            if (!priDataPool || priDataPool < 0x100000000ULL || priDataPool > 0x7FFFFFFFFFFFULL) continue;

            // Iterate sub-pools (+0x10, +0x20, +0x28)
            for (uint64_t subOff : {0x10ULL, 0x20ULL, 0x28ULL}) {
                uintptr_t subPool = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, priDataPool + subOff));
                if (!subPool || subPool < 0x100000000ULL || subPool > 0x7FFFFFFFFFFFULL) continue;

                // subPool has pointers at +0x20, +0x28, +0x30, +0x38, +0x40, +0x48, +0x50
                for (uint64_t pOff = 0x20; pOff <= 0x60; pOff += 8) {
                    uintptr_t propObj = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, subPool + pOff));
                    if (!propObj || propObj < 0x100000000ULL || propObj > 0x7FFFFFFFFFFFULL) continue;

                    int32_t type = MemoryUtils::read<int32_t>(gameTask, propObj + 0x10);
                    int32_t val14 = MemoryUtils::read<int32_t>(gameTask, propObj + 0x14);
                    int32_t val18 = MemoryUtils::read<int32_t>(gameTask, propObj + 0x18);
                    int32_t val1c = MemoryUtils::read<int32_t>(gameTask, propObj + 0x1c);
                    int32_t val20 = MemoryUtils::read<int32_t>(gameTask, propObj + 0x20);

                    static int propLogThrottle = 0;
                    if (++propLogThrottle % 60 == 1) {
                        NSLog(@"[ESP_LOG] [PROP_OBJ] sub:0x%llx+0x%llx obj:0x%llx | type:%d +0x14:%d +0x18:%d +0x1c:%d +0x20:%d",
                              subOff, pOff, (unsigned long long)propObj, type, val14, val18, val1c, val20);
                    }

                    // Look for valid HP value (1..500)
                    if (val18 >= 1 && val18 <= 500) {
                        curHP = val18;
                        maxHP = (val20 >= val18 && val20 <= 500) ? val20 : ((val1c >= val18 && val1c <= 500) ? val1c : 200);
                        if (maxHP < curHP) maxHP = curHP;
                        hpFound = true;
                        break;
                    } else if (val14 >= 1 && val14 <= 500) {
                        curHP = val14;
                        maxHP = 200;
                        hpFound = true;
                        break;
                    }
                }
                if (hpFound) break;
            }
            if (hpFound) break;
        }

        uintptr_t namePtr = StripPAC(MemoryUtils::read<uintptr_t>(gameTask, player + Offsets::Player_OriginalNickName));
        std::string nickname = readIl2CppString(namePtr);
        if (nickname.empty()) nickname = "Enemy";

        // Real-Time Memory Delta Damage Tracker (Tracks exact byte that changes when shot)
        struct PlayerMemSnap {
            uint32_t words[0x600 / 4];
            bool ready = false;
        };
        static std::map<uintptr_t, PlayerMemSnap> sSnaps;
        auto& snap = sSnaps[player];

        for (uint64_t off = 0x300; off <= 0x580; off += 4) {
            uint32_t curWord = MemoryUtils::read<uint32_t>(gameTask, player + off);
            int idx = (int)(off / 4);

            if (snap.ready) {
                uint32_t prevWord = snap.words[idx];
                if (curWord != prevWord) {
                    int diff = (int)prevWord - (int)curWord;
                    if (diff > 0 && diff <= 250 && prevWord <= 500 && curWord <= 500) {
                        NSLog(@"[ESP_LOG] [DAMAGE_HIT_DETECTED] %s | Offset: +0x%llx | HP: %u -> %u (Damage: -%d)",
                              nickname.c_str(), off, prevWord, curWord, diff);
                        curHP = (int)curWord;
                        maxHP = (int)prevWord;
                        hpFound = true;
                    }
                }
            }
            snap.words[idx] = curWord;
        }
        snap.ready = true;

        // Filter out non-player entities (vehicles, props, etc.)
        bool isVehicle = false;
        const char *vehNames[] = {"BattleTrike", "MonsterTruck", "Motorbike", "Pickup", "Amphibian", "SportsCar", "Bike", "Jeep", "TukTuk", "Vehicle", "Boat", "Crows", NULL};
        for (int v = 0; vehNames[v] != NULL; v++) {
            if (nickname.find(vehNames[v]) != std::string::npos) {
                isVehicle = true;
                break;
            }
        }
        if (isVehicle) continue;

        PlayerData pd;
        pd.headWorldPos = headPos;
        pd.toeWorldPos = toePos;
        pd.headScreenPos = headScreen;
        pd.toeScreenPos = toeScreen;
        pd.currentHP = curHP;
        pd.maxHP = (maxHP > 0) ? maxHP : 100;
        pd.teamID = teamID;
        pd.name = nickname;
        pd.distance = headPos.Distance(localPos);
        pd.isVisibleOnScreen = true;
        pd.headTransform = headTransform;
        pd.toeTransform = toeTransform;
        pd.playerPtr = player;

        newPlayers.push_back(pd);
    }

    {
        std::lock_guard<std::mutex> lock(dataMutex);
        this->players = std::move(newPlayers);
        this->cachedScreenWidth = screenWidth;
        this->cachedScreenHeight = screenHeight;
    }

    {
        std::lock_guard<std::mutex> lock(dataMutex);
        char statusBuf[128];
        snprintf(statusBuf, sizeof(statusBuf), "Active ESP: %zu Players", players.size());
        statusMsg = statusBuf;
    }
}


