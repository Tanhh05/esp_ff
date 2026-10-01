# External ESP Free Fire 1.132.1 (iOS ARM64)

Ứng dụng Overlay ESP dành cho thiết bị iPhone 8 Plus (chạy iOS 16.7.11 cài đặt TrollStore 2).

## Tính năng chính:
- **Tích hợp bộ Offset 1.132.1:** Đọc địa chỉ tĩnh `GameFacade_TypeInfo (0x9985B70)`, danh sách `PlayerList`, vị trí `LocalPlayer`, `HeadNode (0x6A0)` & `RightToeNode (0x6F0)`.
- **Tối ưu hiển thị ESP:**
  - **Box ESP:** Khung hình chữ nhật ôm sát chiều cao nhân vật.
  - **Line ESP:** Đường chỉ hướng kẻ từ mép trên màn hình đến đầu đối thủ.
  - **Health Bar:** Thanh máu tự động chuyển màu từ Xanh -> Đỏ tùy tỷ lệ máu còn lại.
  - **NickName & Khoảng cách:** Hiển thị tên UTF-16 và khoảng cách theo mét.
- **Hỗ trợ TrollStore 2:** Có đầy đủ entitlements `task_for_pid-allow`, `com.apple.system-task-ports` để can thiệp bộ nhớ không bị crash.

## Hướng dẫn Biên dịch (Build):
1. Đảm bảo máy Mac/Linux đã cài đặt **Theos**.
2. Mở Terminal tại thư mục này:
   ```bash
   cd /Users/tanh/Downloads/esp_v1/External_ESP_FF_1.132.1
   make clean package
   ```
3. Sau khi build xong, file cài đặt sẽ nằm ở:
   `packages/External_ESP_FF.tipa`
4. AirDrop hoặc gửi file `.tipa` sang **iPhone 8 Plus** và cài qua **TrollStore**.
