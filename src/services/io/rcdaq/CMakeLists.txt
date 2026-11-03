# Automatically set plugin name the same as the directory name
get_filename_component(PLUGIN_NAME ${CMAKE_CURRENT_LIST_DIR} NAME)

# The rcdaq eventlibraries (libNoRootEvent, from online_distribution) are built
# and installed separately and do not provide a CMake package, so find the
# library and the headers directly ($ONLINE_MAIN is their usual install prefix).
# The headers are installed under Event/ (#include <Event/Event.h>), so search
# for Event/Event.h. Without them, the plugin is skipped.
find_library(
  NOROOTEVENT_LIBRARY NoRootEvent
  HINTS $ENV{ONLINE_MAIN}
  PATH_SUFFIXES lib)
find_path(
  NOROOTEVENT_INCLUDE_DIR Event/Event.h
  HINTS $ENV{ONLINE_MAIN}
  PATH_SUFFIXES include)
if(NOT NOROOTEVENT_LIBRARY OR NOT NOROOTEVENT_INCLUDE_DIR)
  message(
    STATUS
      "rcdaq eventlibraries (libNoRootEvent) not found. Skipping rcdaq plugin..."
  )
  return()
endif()

# Function creates ${PLUGIN_NAME}_plugin and ${PLUGIN_NAME}_library targets
# Setting default includes, libraries and installation paths
plugin_add(${PLUGIN_NAME})

# The macro grabs sources as *.cc *.cpp *.c and headers as *.h *.hh *.hpp Then
# correctly sets sources for ${_name}_plugin and ${_name}_library targets Adds
# headers to the correct installation directory
plugin_glob_all(${PLUGIN_NAME})

plugin_include_directories(${PLUGIN_NAME} PRIVATE ${NOROOTEVENT_INCLUDE_DIR})
plugin_link_libraries(${PLUGIN_NAME} ${NOROOTEVENT_LIBRARY} EDM4HEP::edm4hep
                      podio::podio)

# the generator for user plugin projects
install(PROGRAMS mkrcdaqplugin.sh DESTINATION ${CMAKE_INSTALL_BINDIR})
