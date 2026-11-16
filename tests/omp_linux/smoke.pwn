// open.mp (Linux) smoke test for the legacy jit.so plugin: Pawn 3.10 macro
// instructions (push2..5, load.both, const, sysreq.n), calls, jumps and
// switch. Prints "JIT smoke OK" and stops the server. Runs in a public, where
// the JIT reports run time errors ("Run time error N in public ...").

native printf(const format[], {Float,_}:...);
native SetTimer(const funcname[], interval, bool:repeating);
native SendRconCommand(const command[]);

new g1 = 1, g2 = 2, g3 = 3, g4 = 4, g5 = 5;

Join2(a, b) {
	return a * 10 + b;
}

Join5(a, b, c, d, e) {
	return a * 10000 + b * 1000 + c * 100 + d * 10 + e;
}

Join5Ref(&a, &b, &c, &d, &e) {
	a++;
	return a * 10000 + b * 1000 + c * 100 + d * 10 + e;
}

Pick(x) {
	switch (x) {
		case 1: return 10;
		case 2: return 20;
		case 5..9: return 50;
	}
	return -1;
}

Check(id, bool:ok) {
	if (!ok) {
		printf("smoke check %d failed", id);
	}
	return ok ? 0 : 1;
}

main() {}

forward OnGameModeInit();
public OnGameModeInit() {
	printf("smoke start");
	new l1 = 1, l2 = 2, l3 = 3, l4 = 4, l5 = 5;
	new failed = 0;

	failed += Check(1, Join2(1, 2) == 12);
	failed += Check(2, Join5(1, 2, 3, 4, 5) == 12345);
	failed += Check(3, Join2(g1, g2) == 12);
	failed += Check(4, Join5(g1, g2, g3, g4, g5) == 12345);
	failed += Check(5, Join2(l1, l2) == 12);
	failed += Check(6, Join5(l1, l2, l3, l4, l5) == 12345);
	failed += Check(7, Join5Ref(l1, l2, l3, l4, l5) == 22345 && l1 == 2);
	failed += Check(8, g1 + g2 == 3);
	g3 = 7;
	failed += Check(9, g3 == 7);
	failed += Check(10, Pick(1) == 10 && Pick(2) == 20 && Pick(7) == 50 && Pick(3) == -1);

	new sum = 0;
	for (new i = 0; i < 100; i++) {
		sum += i;
	}
	failed += Check(11, sum == 4950);

	printf("sum %d, l1 %d", sum, l1);
	if (failed == 0) {
		printf("JIT smoke OK");
	} else {
		printf("JIT smoke FAILED (%d)", failed);
	}
	SetTimer("Quit", 500, false);
	return 1;
}

forward Quit();
public Quit() {
	SendRconCommand("exit");
}
