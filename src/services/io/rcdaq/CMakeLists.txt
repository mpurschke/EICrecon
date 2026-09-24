# Automatically set plugin name the same as the directory name
get_filename_component(PLUGIN_NAME ${CMAKE_CURRENT_LIST_DIR} NAME)

# Function creates ${PLUGIN_NAME}_plugin and ${PLUGIN_NAME}_library targets
# Setting default includes, libraries and installation paths
plugin_add(${PLUGIN_NAME})

# The macro grabs sources as *.cc *.cpp *.c and headers as *.h *.hh *.hpp Then
# correctly sets sources for ${_name}_plugin and ${_name}_library targets Adds
# headers to the correct installation directory
plugin_glob_all(${PLUGIN_NAME})

# online_distribution/eventlibraries (NoRootEvent) - built/installed
# separately via its own CMakeLists.txt (cmake -S . -B build in
# online_distribution/eventlibraries, then install). Not a CMake package,
# so find it directly like RunControl's CMakeLists.txt does for its
# external DAQ-universe dependencies.
# headers install nested under Event/ (Automake's pkgincludedir
# convention, from AC_INIT(Event,...) - #include <Event/Event.h>, not
# a flat #include <Event.h>), so look for Event/Event.h to get the
# parent dir as NOROOTEVENT_INCLUDE_DIR.
find_library(NOROOTEVENT_LIBRARY NoRootEvent)
find_path(NOROOTEVENT_INCLUDE_DIR Event/Event.h)
if(NOT NOROOTEVENT_LIBRARY OR NOT NOROOTEVENT_INCLUDE_DIR)
  message(FATAL_ERROR "NoRootEvent (from online_distribution/eventlibraries) not found - "
                       "build and install it first")
endif()

plugin_include_directories(${PLUGIN_NAME} PRIVATE ${NOROOTEVENT_INCLUDE_DIR})
plugin_link_libraries(${PLUGIN_NAME} ${NOROOTEVENT_LIBRARY} EDM4HEP::edm4hep podio::podio log_library)
