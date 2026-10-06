// Offsets Header for Free Fire 1.132.1 (iOS ARM64)
#ifndef OFFSETS_1_132_1_H
#define OFFSETS_1_132_1_H

#include <stdint.h>

namespace Offsets {
    // 1. Module Base & Core Static Pointer
    constexpr uint64_t GameFacade_TypeInfo = 0xBB46A50;
    constexpr uint64_t GameFacade_StaticFields = 0xB8;
    constexpr uint64_t CurrentMatchGame = 0x8;

    // 2. MatchGame -> Match & Camera
    constexpr uint64_t MatchGame_m_Match = 0x90;
    constexpr uint64_t MatchGame_CameraControllerManager = 0xD8;
    constexpr uint64_t CameraControllerManager_Camera = 0x20;
    constexpr uint64_t Camera_ViewMatrix = 0x10;
    // Native Camera WorldToClipMatrix (Combined View-Projection 4x4 matrix) at 0x100
    constexpr uint64_t Camera_ViewMatrix_Array = 0x100;

    // Verified Camera Euler Angle Offsets in CameraControllerManager
    constexpr uint64_t CameraControllerManager_Yaw = 0xC8;
    constexpr uint64_t CameraControllerManager_Pitch = 0xCC;
    constexpr uint64_t CameraControllerManager_Yaw2 = 0xEC;
    constexpr uint64_t CameraControllerManager_Pitch2 = 0xF0;
    constexpr uint64_t CameraControllerManager_Yaw3 = 0x114;
    constexpr uint64_t CameraControllerManager_Pitch3 = 0x118;

    // 3. Match -> Players & LocalPlayer
    constexpr uint64_t Match_LocalPlayer = 0xD8;
    constexpr uint64_t Match_PlayerList_List = 0x158;
    constexpr uint64_t Match_PlayerDict = 0x128;
    constexpr uint64_t Il2CppList_Items = 0x10;
    constexpr uint64_t Il2CppList_Count = 0x18;

    // 4. Player Bones & Transforms
    constexpr uint64_t Player_MainCameraTransform = 0x3E8;
    constexpr uint64_t Player_HeadNode = 0x6A0;
    constexpr uint64_t Player_RightToeNode = 0x6F0;
    constexpr uint64_t ITransformNode_Transform = 0x10;

    // 5. Team ID & Filtering
    constexpr uint64_t Player_PlayerIDStruct = 0x408;
    constexpr uint64_t BEADLMGGGGL_TeamID = 0x18;

    // 6. Player Info
    constexpr uint64_t Player_OriginalNickName = 0x498;
    constexpr uint64_t SystemString_Chars = 0x14;
    
    constexpr uint64_t Player_PRIDataPool = 0x70;
    constexpr uint64_t IPRIDataPool_Array = 0x10;
    constexpr uint64_t IPRIDataPool_Item = 0x20;
    constexpr uint64_t IPRIDataPool_Value = 0x18;

    // 7. Weapon & Silent Aim Offsets
    constexpr uint64_t Player_WeaponManager = 0x518;
    constexpr uint64_t Player_CurrentWeapon = 0x520;
    constexpr uint64_t Player_WeaponController = 0x538;
}

#endif // OFFSETS_1_132_1_H
