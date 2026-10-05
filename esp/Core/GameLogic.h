#ifndef GAME_LOGIC_H
#define GAME_LOGIC_H

#include <vector>
#include <string>
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
};

class GameLogic {
public:
    static GameLogic& getInstance() {
        static GameLogic instance;
        return instance;
    }

    bool initialize();
    void updateData(float screenWidth, float screenHeight);
    const std::vector<PlayerData>& getPlayers() const { return players; }
    std::string getStatusString() const { return statusMsg; }
    
    bool getBestTarget(Vector2 screenCenter, float fovRadius, int boneType, PlayerData& outTarget);
    static Vector3 calculateAngle(Vector3 localPos, Vector3 targetPos);
    
private:
    mach_port_t gameTask = 0;
    pid_t gamePid = 0;
    uintptr_t unityFrameworkBase = 0;
    std::string statusMsg = "Not initialized";
    std::vector<PlayerData> players;

    std::string readIl2CppString(uintptr_t stringPtr);
};


#endif // GAME_LOGIC_H
