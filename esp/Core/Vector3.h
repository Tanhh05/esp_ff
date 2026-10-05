#ifndef VECTOR3_H
#define VECTOR3_H

#include <cmath>

struct Vector3 {
    float x, y, z;

    Vector3() : x(0.0f), y(0.0f), z(0.0f) {}
    Vector3(float _x, float _y, float _z) : x(_x), y(_y), z(_z) {}

    float Distance(const Vector3 &other) const {
        float dx = x - other.x;
        float dy = y - other.y;
        float dz = z - other.z;
        return std::sqrt(dx * dx + dy * dy + dz * dz);
    }

    Vector3 operator-(const Vector3 &o) const { return Vector3(x - o.x, y - o.y, z - o.z); }
    Vector3 operator+(const Vector3 &o) const { return Vector3(x + o.x, y + o.y, z + o.z); }
    Vector3 operator*(float s) const { return Vector3(x * s, y * s, z * s); }
};

struct Vector2 {
    float x, y;
    Vector2() : x(0.0f), y(0.0f) {}
    Vector2(float _x, float _y) : x(_x), y(_y) {}

    Vector2 operator-(const Vector2 &o) const { return Vector2(x - o.x, y - o.y); }
    Vector2 operator+(const Vector2 &o) const { return Vector2(x + o.x, y + o.y); }
    Vector2 operator*(float s) const { return Vector2(x * s, y * s); }
};

#endif // VECTOR3_H
