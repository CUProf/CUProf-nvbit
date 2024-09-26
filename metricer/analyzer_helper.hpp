#pragma once

#include <string>
#include <sstream>

std::string format_size(size_t size) {
    std::ostringstream os;
    os.precision(2);
    os << std::fixed;
    if (size <= 1024) {
        os << size << " bytes";
    } else if (size <= 1048576) {
        os << (size / 1024.0);
        os << " KB";
    } else if (size <= 1073741824ULL) {
        os << size / 1048576.0;
        os << " MB";
    } else {
        os << size / 1073741824.0;
        os << " GB";
    }
    return os.str();
}

std::string format_number(uint64_t number) {
    std::ostringstream os;
    os.precision(2);
    os << std::fixed;
    if (number <= 1000) {
        os << number;
    } else if (number <= 1000000) {
        os << number / 1000.0;
        os << " K";
    } else if (number <= 1000000000) {
        os << number / 1000000.0;
        os << " M";
    } else {
        os << number / 1000000000.0;
        os << " B";
    }
    return os.str();
}