#pragma once

#include <string>
#include <sstream>
#include <ctime>

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


std::string getCurrentDateTime() {
    // Get current time as time_t
    std::time_t now = std::time(nullptr);
    
    // Convert time_t to tm struct for local time
    std::tm* local_time = std::localtime(&now);
    
    // Create a stringstream to format the date and time
    std::stringstream ss;
    ss << (local_time->tm_year + 1900) << "-"  // Year
       << (local_time->tm_mon + 1) << "-"      // Month (tm_mon is 0-11)
       << local_time->tm_mday << "_"           // Day of the month
       << local_time->tm_hour << "-"           // Hour
       << local_time->tm_min << "-"            // Minute
       << local_time->tm_sec;                  // Second

    // Convert the stringstream to string and return
    return ss.str();
}