case "$CONFIGURATION" in
*-development) flutter_flavor=development ;;
*-staging) flutter_flavor=staging ;;
*-production) flutter_flavor=production ;;
*) flutter_flavor= ;;
esac

if [ -n "$flutter_flavor" ]; then
	FLAVOR="$flutter_flavor"
	export FLAVOR
	case "$FLUTTER_TARGET" in
	*/flutter_test_listener.*/listener.dart)
		if [ -f "$FLUTTER_TARGET" ]; then
			flutter_flavor=
		fi
		;;
	esac
	if [ -n "$flutter_flavor" ]; then
		FLUTTER_TARGET="lib/main_$flutter_flavor.dart"
		export FLUTTER_TARGET
	fi
fi
