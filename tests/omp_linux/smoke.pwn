// open.mp (Linux) smoke test for the legacy jit.so plugin: Pawn 3.10 macro
// instructions (push2..5, load.both, const, sysreq.n), calls, jumps and
// switch. Prints "JIT smoke OK" and stops the server.

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

main() {
	new l1 = 1, l2 = 2, l3 = 3, l4 = 4, l5 = 5;
	new ok = 1;

	if (Join2(1, 2) != 12) ok = 0;
	if (Join5(1, 2, 3, 4, 5) != 12345) ok = 0;
	if (Join2(g1, g2) != 12) ok = 0;
	if (Join5(g1, g2, g3, g4, g5) != 12345) ok = 0;
	if (Join2(l1, l2) != 12) ok = 0;
	if (Join5(l1, l2, l3, l4, l5) != 12345) ok = 0;
	if (Join5Ref(l1, l2, l3, l4, l5) != 22345 || l1 != 2) ok = 0;
	if (g1 + g2 != 3) ok = 0;
	g3 = 7;
	if (g3 != 7) ok = 0;
	if (Pick(1) != 10 || Pick(2) != 20 || Pick(7) != 50 || Pick(3) != -1) ok = 0;

	new sum = 0;
	for (new i = 0; i < 100; i++) {
		sum += i;
	}
	if (sum != 4950) ok = 0;

	printf("sum %d, l1 %d", sum, l1);
	if (ok) {
		printf("JIT smoke OK");
	} else {
		printf("JIT smoke FAILED");
	}
}

public OnGameModeInit() {
	SetTimer("Quit", 500, false);
	return 1;
}

forward Quit();
public Quit() {
	SendRconCommand("exit");
}
