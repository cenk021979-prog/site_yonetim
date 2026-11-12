#ifndef RUNNER_CLIPBOARD_IMAGE_H_
#define RUNNER_CLIPBOARD_IMAGE_H_

#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>

struct ClipboardImageResult {
  std::vector<uint8_t> bytes;
  std::string error;
};

ClipboardImageResult ReadClipboardImage(HWND owner);

#endif  // RUNNER_CLIPBOARD_IMAGE_H_
