#include "iphone_arkit_head_tracker_module.h"

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/config/engine.h"
#else
#include "core/engine.h"
#endif

#include "iphone_arkit_head_tracker.h"

IPhoneARKitHeadTracker *iphone_arkit_head_tracker = nullptr;

void register_iphone_arkit_head_tracker_types() {
	iphone_arkit_head_tracker = memnew(IPhoneARKitHeadTracker);
	Engine::get_singleton()->add_singleton(Engine::Singleton("IPhoneARKitHeadTracker", iphone_arkit_head_tracker));
}

void unregister_iphone_arkit_head_tracker_types() {
	if (iphone_arkit_head_tracker) {
		memdelete(iphone_arkit_head_tracker);
		iphone_arkit_head_tracker = nullptr;
	}
}
