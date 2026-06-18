#ifndef IPHONE_ARKIT_HEAD_TRACKER_H
#define IPHONE_ARKIT_HEAD_TRACKER_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/error/error_list.h"
#include "core/math/vector3.h"
#include "core/object/object.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#else
#include "core/object.h"
#endif

#ifdef __OBJC__
@class IPhoneARKitHeadTrackerSession;
typedef IPhoneARKitHeadTrackerSession IPhoneARKitHeadTrackerSessionHandle;
#else
typedef void IPhoneARKitHeadTrackerSessionHandle;
#endif

class IPhoneARKitHeadTracker : public Object {
	GDCLASS(IPhoneARKitHeadTracker, Object);

	static IPhoneARKitHeadTracker *instance;
	static void _bind_methods();

	IPhoneARKitHeadTrackerSessionHandle *session;
	Vector3 latest_position_meters;
	bool tracking_supported;
	bool tracking_started;
	bool face_tracked;
	String status_message;
	uint64_t frame_count;

public:
	static IPhoneARKitHeadTracker *get_singleton();

	Error start_tracking();
	void stop_tracking();
	bool is_tracking() const;
	Vector3 get_screen_local_head_position_meters() const;
	Dictionary get_tracking_status() const;
	void reset_tracking_reference();

	void update_head_position(const Vector3 &position_meters, bool tracked);
	void update_support_state(bool supported, const String &message);

	IPhoneARKitHeadTracker();
	~IPhoneARKitHeadTracker();
};

#endif
