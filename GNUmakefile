ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make
APP_NAME = FileViewer
FileViewer_OBJC_FILES = main.m FVApplication.m FVWindow.m FVModel.m FVOperations.m FVIconView.m FVLauncher.m
FileViewer_HEADER_FILES = FVApplication.h FVWindow.h FVModel.h FVOperations.h FVIconView.h FVLauncher.h
FileViewer_RESOURCE_FILES = Resources/FileViewer.png
FileViewer_APPLICATION_ICON = FileViewer.png
FileViewer_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
include $(GNUSTEP_MAKEFILES)/application.make
