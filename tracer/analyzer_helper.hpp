#pragma once

#include <ctime>
#include <sstream>
#include <sys/stat.h>   // for folder creation

void checkFolderExistance(std::string folder_name) {
    // Check if the folder exists
    struct stat info;
    if (stat(folder_name.c_str(), &info) != 0) {
        // Folder does not exist, create it
        if (mkdir(folder_name.c_str(), 0777) == 0) {
            fprintf(stdout, "Folder %s created successfully.\n", folder_name.c_str());
        } else {
            fprintf(stderr, "Failed to create folder %s.\n", folder_name.c_str());
        }
    } else if (info.st_mode & S_IFDIR) {
        // Folder exists
        // fprintf(stdout, "Folder %s already exists.\n", folder_name.c_str());
    } else {
        // fprintf(stderr, "%s exists but is not a directory.\n", folder_name.c_str());
    }
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