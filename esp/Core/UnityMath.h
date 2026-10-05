#ifndef UNITY_MATH_H
#define UNITY_MATH_H

#include "Vector3.h"
#include "MemoryUtils.h"
#include <mach/mach.h>
#include <cmath>

struct Matrix4x4 {
    float m[16];
};

class UnityMath {
public:
    static bool WorldToScreen(Vector3 worldPos, Matrix4x4 viewMatrix, float screenWidth, float screenHeight, Vector2 &screenPos) {
        // Unity Native Column-Major WorldToClipMatrix (verified via UnityFramework ASM @ 0xBF00EC)
        // W: Row 3 = m[3]*x + m[7]*y + m[11]*z + m[15]
        float w = viewMatrix.m[3] * worldPos.x + viewMatrix.m[7] * worldPos.y + viewMatrix.m[11] * worldPos.z + viewMatrix.m[15];
        
        // Point is behind or too close to camera plane
        if (w <= 0.05f) {
            return false;
        }

        // X: Row 0 = m[0]*x + m[4]*y + m[8]*z + m[12]
        float clipX = viewMatrix.m[0] * worldPos.x + viewMatrix.m[4] * worldPos.y + viewMatrix.m[8] * worldPos.z + viewMatrix.m[12];
        // Y: Row 1 = m[1]*x + m[5]*y + m[9]*z + m[13]
        float clipY = viewMatrix.m[1] * worldPos.x + viewMatrix.m[5] * worldPos.y + viewMatrix.m[9] * worldPos.z + viewMatrix.m[13];

        float ndcX = clipX / w;
        float ndcY = clipY / w;

        // Convert Normalized Device Coordinates (NDC) to Screen Coordinates in UIKit space
        float x = (screenWidth / 2.0f) + (ndcX * (screenWidth / 2.0f));
        float y = (screenHeight / 2.0f) - (ndcY * (screenHeight / 2.0f));

        screenPos.x = x;
        screenPos.y = y;

        // Filter out points far off-screen
        if (screenPos.x < -150.0f || screenPos.x > screenWidth + 150.0f ||
            screenPos.y < -150.0f || screenPos.y > screenHeight + 150.0f) {
            return false;
        }

        return true;
    }

    static Vector3 GetTransformPosition(mach_port_t task, uintptr_t transformPtr) {
        Vector3 result{0, 0, 0};
        if (!task || !transformPtr) return result;

        auto stripPAC = [](uintptr_t ptr) -> uintptr_t {
            if (!ptr) return 0;
            return ptr & 0x0000007FFFFFFFFFULL;
        };

        uintptr_t nativeTF = stripPAC(MemoryUtils::read<uintptr_t>(task, transformPtr + 0x10));
        if (!nativeTF || nativeTF < 0x100000000) {
            nativeTF = transformPtr;
        }

        uintptr_t matrix = stripPAC(MemoryUtils::read<uintptr_t>(task, nativeTF + 0x38));
        int32_t index = MemoryUtils::read<int32_t>(task, nativeTF + 0x40);
        if (!matrix || index < 0 || index > 100000) {
            return result;
        }

        uintptr_t matrix_list = stripPAC(MemoryUtils::read<uintptr_t>(task, matrix + 0x18));
        uintptr_t matrix_indices = stripPAC(MemoryUtils::read<uintptr_t>(task, matrix + 0x20));
        if (!matrix_list || !matrix_indices) {
            return result;
        }

        struct TMatrix {
            float posX, posY, posZ, posW;
            float rotX, rotY, rotZ, rotW;
            float scaleX, scaleY, scaleZ, scaleW;
        };

        TMatrix curData{};
        if (!MemoryUtils::read_raw(task, matrix_list + (index * sizeof(TMatrix)), &curData, sizeof(curData))) {
            return result;
        }

        result.x = curData.posX;
        result.y = curData.posY;
        result.z = curData.posZ;

        int32_t transformIndex = MemoryUtils::read<int32_t>(task, matrix_indices + (index * sizeof(int32_t)));
        int maxDepth = 30;

        while (transformIndex >= 0 && maxDepth-- > 0) {
            TMatrix tMatrix{};
            if (!MemoryUtils::read_raw(task, matrix_list + (transformIndex * sizeof(TMatrix)), &tMatrix, sizeof(tMatrix))) {
                break;
            }

            float rotX = tMatrix.rotX;
            float rotY = tMatrix.rotY;
            float rotZ = tMatrix.rotZ;
            float rotW = tMatrix.rotW;

            float scaleX = result.x * tMatrix.scaleX;
            float scaleY = result.y * tMatrix.scaleY;
            float scaleZ = result.z * tMatrix.scaleZ;

            result.x = tMatrix.posX + scaleX +
                        (scaleX * ((rotY * rotY * -2.0f) - (rotZ * rotZ * 2.0f))) +
                        (scaleY * ((rotW * rotZ * -2.0f) - (rotY * rotX * -2.0f))) +
                        (scaleZ * ((rotZ * rotX * 2.0f) - (rotW * rotY * -2.0f)));
            result.y = tMatrix.posY + scaleY +
                        (scaleX * ((rotX * rotY * 2.0f) - (rotW * rotZ * -2.0f))) +
                        (scaleY * ((rotZ * rotZ * -2.0f) - (rotX * rotX * 2.0f))) +
                        (scaleZ * ((rotW * rotX * -2.0f) - (rotZ * rotY * -2.0f)));
            result.z = tMatrix.posZ + scaleZ +
                        (scaleX * ((rotW * rotY * -2.0f) - (rotX * rotZ * -2.0f))) +
                        (scaleY * ((rotY * rotZ * 2.0f) - (rotW * rotX * -2.0f))) +
                        (scaleZ * ((rotX * rotX * -2.0f) - (rotY * rotY * 2.0f)));

            transformIndex = MemoryUtils::read<int32_t>(task, matrix_indices + (transformIndex * sizeof(int32_t)));
        }

        return result;
    }

    struct Quaternion {
        float x, y, z, w;
    };

    static inline Quaternion LookRotation(Vector3 forward) {
        float mag = sqrtf(forward.x * forward.x + forward.y * forward.y + forward.z * forward.z);
        if (mag < 0.0001f) return Quaternion{0.0f, 0.0f, 0.0f, 1.0f};
        forward.x /= mag;
        forward.y /= mag;
        forward.z /= mag;

        Vector3 up{0.0f, 1.0f, 0.0f};
        if (fabsf(forward.y) > 0.999f) {
            up = Vector3{0.0f, 0.0f, (forward.y > 0.0f) ? -1.0f : 1.0f};
        }

        Vector3 right{
            up.y * forward.z - up.z * forward.y,
            up.z * forward.x - up.x * forward.z,
            up.x * forward.y - up.y * forward.x
        };
        float rMag = sqrtf(right.x * right.x + right.y * right.y + right.z * right.z);
        if (rMag > 0.0001f) {
            right.x /= rMag; right.y /= rMag; right.z /= rMag;
        }

        up = Vector3{
            forward.y * right.z - forward.z * right.y,
            forward.z * right.x - forward.x * right.z,
            forward.x * right.y - forward.y * right.x
        };

        float m00 = right.x, m01 = up.x, m02 = forward.x;
        float m10 = right.y, m11 = up.y, m12 = forward.y;
        float m20 = right.z, m21 = up.z, m22 = forward.z;

        float tr = m00 + m11 + m22;
        Quaternion q;
        if (tr > 0.0f) {
            float s = sqrtf(tr + 1.0f) * 2.0f;
            q.w = 0.25f * s;
            q.x = (m21 - m12) / s;
            q.y = (m02 - m20) / s;
            q.z = (m10 - m01) / s;
        } else if ((m00 > m11) && (m00 > m22)) {
            float s = sqrtf(1.0f + m00 - m11 - m22) * 2.0f;
            q.w = (m21 - m12) / s;
            q.x = 0.25f * s;
            q.y = (m01 + m10) / s;
            q.z = (m02 + m20) / s;
        } else if (m11 > m22) {
            float s = sqrtf(1.0f + m11 - m00 - m22) * 2.0f;
            q.w = (m02 - m20) / s;
            q.x = (m01 + m10) / s;
            q.y = 0.25f * s;
            q.z = (m12 + m21) / s;
        } else {
            float s = sqrtf(1.0f + m22 - m00 - m11) * 2.0f;
            q.w = (m10 - m01) / s;
            q.x = (m02 + m20) / s;
            q.y = (m12 + m21) / s;
            q.z = 0.25f * s;
        }
        return q;
    }

    static bool SetTransformRotation(mach_port_t task, uintptr_t transformPtr, Quaternion rot) {
        if (!task || !transformPtr) return false;

        auto stripPAC = [](uintptr_t ptr) -> uintptr_t {
            if (!ptr) return 0;
            return ptr & 0x0000007FFFFFFFFFULL;
        };

        uintptr_t nativeTF = stripPAC(MemoryUtils::read<uintptr_t>(task, transformPtr + 0x10));
        if (!nativeTF || nativeTF < 0x100000000) {
            nativeTF = transformPtr;
        }

        uintptr_t matrix = stripPAC(MemoryUtils::read<uintptr_t>(task, nativeTF + 0x38));
        int32_t index = MemoryUtils::read<int32_t>(task, nativeTF + 0x40);
        if (!matrix || index < 0 || index > 100000) {
            return false;
        }

        uintptr_t matrix_list = stripPAC(MemoryUtils::read<uintptr_t>(task, matrix + 0x18));
        if (!matrix_list) return false;

        // Offset of rotX in TMatrix is +0x10 (after posX, posY, posZ, posW)
        uintptr_t rotAddr = matrix_list + (index * 48) + 16;
        float rotBuf[4] = {rot.x, rot.y, rot.z, rot.w};
        return MemoryUtils::write_raw(task, rotAddr, rotBuf, sizeof(rotBuf));
    }
};

#endif // UNITY_MATH_H

