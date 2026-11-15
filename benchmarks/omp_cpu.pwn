// CPU-bound micro benchmarks: interpreter vs JIT. Each test prints
// "[BENCH] <name>: <ms> ms (check <n>)"; the checksum proves the work ran
// and must match between modes.
#include <open.mp>

#define SORT_SIZE 4000

new gArr[SORT_SIZE];

stock Fib(n) {
	return n < 2 ? n : Fib(n - 1) + Fib(n - 2);
}

stock Report(const name[], start, check) {
	printf("[BENCH] %s: %d ms (check %d)", name, GetTickCount() - start, check);
}

main() {
	new t, x;

	// Integer arithmetic (LCG) - pure opcodes.
	t = GetTickCount(), x = 1;
	for (new i = 0; i < 50000000; i++) {
		x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
	}
	Report("int_arith (50M LCG)", t, x);

	// Float math - float natives the JIT turns into FPU instructions.
	t = GetTickCount();
	new Float:f = 1.0;
	for (new i = 0; i < 10000000; i++) {
		f = floatsqroot(f * 1.0001 + 1.0) / 2.0 + floatabs(-0.5);
	}
	Report("float_math (10M)", t, floatround(f * 1000.0));

	// Array access - bubble sort of a reversed array.
	for (new i = 0; i < SORT_SIZE; i++) gArr[i] = SORT_SIZE - i;
	t = GetTickCount();
	for (new i = 0; i < SORT_SIZE - 1; i++) {
		for (new j = 0; j < SORT_SIZE - 1 - i; j++) {
			if (gArr[j] > gArr[j + 1]) {
				x = gArr[j], gArr[j] = gArr[j + 1], gArr[j + 1] = x;
			}
		}
	}
	Report("array_sort (bubble 4000)", t, gArr[0] + gArr[SORT_SIZE - 1]);

	// Function calls - naive recursion.
	t = GetTickCount();
	x = Fib(30);
	Report("func_calls (fib 30)", t, x);

	// Native-heavy string work - JIT only speeds up the glue around natives.
	new str[128], len = 0;
	t = GetTickCount();
	for (new i = 0; i < 300000; i++) {
		format(str, sizeof(str), "player %d hp %.2f name %s", i, 100.0, "Budi");
		len += strlen(str) + strfind(str, "name");
	}
	Report("string_format (300k)", t, len);

	// Raw native call overhead.
	t = GetTickCount(), x = 0;
	for (new i = 0; i < 5000000; i++) {
		x += strlen("hello world");
	}
	Report("native_calls (5M strlen)", t, x);

	print("[BENCH] done");
	SendRconCommand("exit");
}

public OnGameModeInit() {
	return 1;
}
