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
        // Free Fire ViewMatrix on iOS ARM64 (Row-Major):
        // W is in row 4: m[12] * x + m[13] * y + m[14] * z + m[15]
        // X is in row 1: m[0] * x + m[1] * y + m[2] * z + m[3]
        // Y is in row 2: m[4] * x + m[5] * y + m[6] * z + m[7]
        float w = viewMatrix.m[12] * worldPos.x + viewMatrix.m[13] * worldPos.y + viewMatrix.m[14] * worldPos.z + viewMatrix.m[15];
        
        // Check if point is behind or too close to camera
        if (w <= 0.01f) {
            return false;
        }

        float clipX = viewMatrix.m[0] * worldPos.x + viewMatrix.m[1] * worldPos.y + viewMatrix.m[2] * worldPos.z + viewMatrix.m[3];
        float clipY = viewMatrix.m[4] * worldPos.x + viewMatrix.m[5] * worldPos.y + viewMatrix.m[6] * worldPos.z + viewMatrix.m[7];

        float ndcX = clipX / w;
        float ndcY = clipY / w;

        // Convert Normalized Device Coordinates (NDC) to Screen Coordinates
        float x = (screenWidth / 2.0f) + (ndcX * (screenWidth / 2.0f));
        float y = (screenHeight / 2.0f) - (ndcY * (screenHeight / 2.0f));

        screenPos.x = x;
        screenPos.y = y;

        // Filter out extreme off-screen points
        if (screenPos.x < -200.0f || screenPos.x > screenWidth + 200.0f ||
            screenPos.y < -200.0f || screenPos.y > screenHeight + 200.0f) {
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
};

#endif // UNITY_MATH_H

