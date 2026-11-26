#include "flutter_window.h"

#include <dwrite.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

#include "utils.h"

namespace {

flutter::EncodableList AvailableFontFamilies() {
  using Microsoft::WRL::ComPtr;
  flutter::EncodableList names;
  ComPtr<IDWriteFactory> factory;
  ComPtr<IDWriteFontCollection> collection;
  if (FAILED(DWriteCreateFactory(
          DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
          reinterpret_cast<IUnknown **>(factory.GetAddressOf()))) ||
      FAILED(factory->GetSystemFontCollection(&collection, TRUE))) {
    return names;
  }

  for (UINT32 i = 0; i < collection->GetFontFamilyCount(); ++i) {
    ComPtr<IDWriteFontFamily> family;
    ComPtr<IDWriteLocalizedStrings> strings;
    if (FAILED(collection->GetFontFamily(i, &family)) ||
        FAILED(family->GetFamilyNames(&strings))) {
      continue;
    }
    // Use the English family name when available so Office documents retain
    // names that can be resolved across different display languages.
    UINT32 index = 0;
    BOOL found = FALSE;
    if (FAILED(strings->FindLocaleName(L"en-us", &index, &found)) || !found) {
      index = 0;
    }
    UINT32 length = 0;
    if (FAILED(strings->GetStringLength(index, &length))) {
      continue;
    }
    std::vector<wchar_t> name(length + 1);
    if (SUCCEEDED(strings->GetString(index, name.data(), length + 1))) {
      names.emplace_back(Utf8FromUtf16(name.data()));
    }
  }
  return names;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  flutter::MethodChannel<flutter::EncodableValue> catalog(
      flutter_controller_->engine()->messenger(), "crispoffice/font-catalog",
      &flutter::StandardMethodCodec::GetInstance());
  catalog.SetMethodCallHandler([](const auto &call, auto result) {
    if (call.method_name() == "availableFamilies") {
      result->Success(flutter::EncodableValue(AvailableFontFamilies()));
    } else {
      result->NotImplemented();
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
