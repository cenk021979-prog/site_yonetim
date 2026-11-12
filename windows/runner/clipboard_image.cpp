#include "clipboard_image.h"

#include <objidl.h>
#include <gdiplus.h>

#include <memory>

namespace {
constexpr SIZE_T kMaxBytes = 50 * 1024 * 1024;
constexpr uint64_t kMaxPixels = 40000000;

struct ClipboardCloser {
  ~ClipboardCloser() { CloseClipboard(); }
};

struct GlobalUnlocker {
  HANDLE handle;
  ~GlobalUnlocker() { GlobalUnlock(handle); }
};

struct GdiCloser {
  ULONG_PTR token;
  ~GdiCloser() { Gdiplus::GdiplusShutdown(token); }
};

ClipboardImageResult CopyGlobalBytes(HANDLE handle) {
  const SIZE_T size = GlobalSize(handle);
  if (size == 0 || size > kMaxBytes) return {{}, "CLIPBOARD_IMAGE_TOO_LARGE"};
  const auto* data = static_cast<const uint8_t*>(GlobalLock(handle));
  if (!data) return {{}, "CLIPBOARD_IMAGE_UNAVAILABLE"};
  GlobalUnlocker unlock{handle};
  return {std::vector<uint8_t>(data, data + size), ""};
}
}  // namespace

ClipboardImageResult ReadClipboardImage(HWND owner) {
  if (!OpenClipboard(owner)) return {{}, "CLIPBOARD_BUSY"};
  ClipboardCloser close;

  // Snipping Tool/browser can supply PNG directly. Never open paths or shell out.
  const UINT png = RegisterClipboardFormatW(L"PNG");
  if (png && IsClipboardFormatAvailable(png)) {
    HANDLE handle = GetClipboardData(png);
    if (handle) return CopyGlobalBytes(handle);
  }
  if (!IsClipboardFormatAvailable(CF_BITMAP) &&
      !IsClipboardFormatAvailable(CF_DIB) &&
      !IsClipboardFormatAvailable(CF_DIBV5)) return {};

  // Windows synthesizes CF_BITMAP from DIB/DIBV5. Encode to PNG while the
  // clipboard is open; the borrowed HBITMAP belongs to Windows and is not freed.
  const auto handle = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
  BITMAP info{};
  if (!handle || !GetObject(handle, sizeof(info), &info) || info.bmWidth <= 0 ||
      info.bmHeight <= 0) return {{}, "CLIPBOARD_IMAGE_UNAVAILABLE"};
  const auto width = static_cast<uint64_t>(info.bmWidth);
  const auto height = static_cast<uint64_t>(info.bmHeight);
  if (width > 12000 || height > 12000 || width * height > kMaxPixels)
    return {{}, "CLIPBOARD_IMAGE_TOO_LARGE"};

  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok)
    return {{}, "CLIPBOARD_IMAGE_UNAVAILABLE"};
  GdiCloser shutdown{token};
  std::unique_ptr<Gdiplus::Bitmap> bitmap(Gdiplus::Bitmap::FromHBITMAP(handle, nullptr));
  if (!bitmap || bitmap->GetLastStatus() != Gdiplus::Ok)
    return {{}, "CLIPBOARD_IMAGE_UNAVAILABLE"};
  // Public Windows PNG encoder CLSID (GDI+ image codec).
  const CLSID encoder = {0x557cf406, 0x1a04, 0x11d3,
                        {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)))
    return {{}, "CLIPBOARD_IMAGE_UNAVAILABLE"};
  const auto status = bitmap->Save(stream, &encoder, nullptr);
  ClipboardImageResult result{{}, "CLIPBOARD_IMAGE_UNAVAILABLE"};
  if (status == Gdiplus::Ok) {
    HGLOBAL memory = nullptr;
    STATSTG stat{};
    if (SUCCEEDED(GetHGlobalFromStream(stream, &memory)) &&
        SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME))) {
      if (stat.cbSize.HighPart || stat.cbSize.LowPart > kMaxBytes) {
        result.error = "CLIPBOARD_IMAGE_TOO_LARGE";
      } else {
        result = CopyGlobalBytes(memory);
        // GlobalSize may include allocator padding; keep only encoded stream bytes.
        if (result.error.empty()) result.bytes.resize(stat.cbSize.LowPart);
      }
    }
  }
  stream->Release();
  return result;
}
