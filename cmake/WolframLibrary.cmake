
#
# Update this value as needed
#
set(MAX_EXPECTED_WOLFRAMLIBRARY_VERSION 6 CACHE STRING "Max expected WolframLibrary version")

macro(ParseWolframLibraryHeader)

	if(NOT EXISTS ${WOLFRAMLIBRARY_INCLUDE_DIR})
	message(FATAL_ERROR "WOLFRAMLIBRARY_INCLUDE_DIR does not exist. WOLFRAMLIBRARY_INCLUDE_DIR: ${WOLFRAMLIBRARY_INCLUDE_DIR}")
	endif()

	set(WOLFRAMLIBRARY_HEADER ${WOLFRAMLIBRARY_INCLUDE_DIR}/WolframLibrary.h)

	if(NOT EXISTS ${WOLFRAMLIBRARY_HEADER})
	message(FATAL_ERROR "WOLFRAMLIBRARY_HEADER does not exist. WOLFRAMLIBRARY_HEADER: ${WOLFRAMLIBRARY_HEADER}")
	endif()

	file(READ ${WOLFRAMLIBRARY_HEADER} filedata)

	string(REGEX MATCH "#define WolframLibraryVersion ([0-9]+)" _ ${filedata})

	set(WOLFRAMLIBRARY_VERSION ${CMAKE_MATCH_1})

	if(NOT DEFINED WOLFRAMLIBRARY_VERSION)
	message(FATAL_ERROR "WOLFRAMLIBRARY_VERSION was not set.")
	endif()

endmacro(ParseWolframLibraryHeader)
