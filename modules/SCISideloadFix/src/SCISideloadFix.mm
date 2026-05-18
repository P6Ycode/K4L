#import "Header.h"

__attribute__((constructor)) static void init() {
	rebindSecFuncs();
}
