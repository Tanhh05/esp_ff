#ifndef GAME_LOGIC_H
#define GAME_LOGIC_H

#include <vector>
#include <string>
#include <mutex>
#include "Vector3.h"
#include "UnityMath.h"

struct PlayerData {
    Vector3 headWorldPos;
    Vector3 toeWorldPos;
    Vector2 headScreenPos;
    Vector2 toeScreenPos;
    int currentHP;
    int maxHP;
    uint8_t teamID;
    std::string name;
    float distance;
    bool isVisibleOnScreen;
    uintptr_t headTransform = 0;
    uintptr_t toeTransform = 0;
    uintptr_t playerPtr = 0;
};

class GameLogic {
public:
    static GameLogic& getInstance() {
        static GameLogic instance;
        return instance;
    }

    bool initialize();
    void updateData(float screenWidth, float screenHeight);
    std::vector<PlayerData> getPlayers() const {
        std::lock_guard<std::mutex> lock(dataMutex);
        return players;
    }
    std::string getStatusString() const {
        std::lock_guard<std::mutex> lock(dataMutex);
        return statusMsg;
    }

private:
    mutable std::mutex dataMutex;
    mach_port_t gameTask = 0;
    pid_t gamePid = 0;
    uintptr_t unityFrameworkBase = 0;
    uintptr_t cachedCameraMgr = 0;
    float cachedScreenWidth = 736.0f;
    float cachedScreenHeight = 414.0f;
    Vector3 cachedLocalPos{0, 0, 0};
    std::string statusMsg = "Not initialized";
    std::vector<PlayerData> players;

    std::string readIl2CppString(uintptr_t stringPtr);
};

#endif // GAME_LOGIC_H

