import 'package:flutter/material.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// === Firebase Web Options (tus credenciales) ===
const FirebaseOptions _firebaseWebOptions = FirebaseOptions(
  apiKey: "AIzaSyDWG1-YfJCQjAZKB9yZ7uRZzNwZbaj4RBc",
  authDomain: "trucorank-44c29.firebaseapp.com",
  projectId: "trucorank-44c29",
  storageBucket: "trucorank-44c29.appspot.com",
  messagingSenderId: "61789687955",
  appId: "1:61789687955:web:431b111844a3af8fbe3d66",
);

/// Crea balances/{uid} si no existe
Future<void> _ensureBalanceDoc() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final ref = FirebaseFirestore.instance.collection('balances').doc(uid);
  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({'available': 0.0, 'locked': 0.0});
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _firebaseWebOptions);

  // Login anónimo (DEV)
  await FirebaseAuth.instance.signInAnonymously();

  // Asegura que exista balances/{uid}
  await _ensureBalanceDoc();

  runApp(const TrucoRankApp());
}

class TrucoRankApp extends StatelessWidget {
  const TrucoRankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Truco Rank',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = FirebaseFirestore.instance;

  String _fmt(double? v) => v == null ? '--' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Truco Rank — Demo (sin cuotas)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset UID (DEV)',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              await FirebaseAuth.instance.signInAnonymously();
              await _ensureBalanceDoc();

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Nuevo UID: ${FirebaseAuth.instance.currentUser?.uid}'),
                ),
              );
              setState(() {});
            },
          ),
        ],
      ),

      // Crear mesa rápida (DEV)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearMesaDemo,
        icon: const Icon(Icons.add),
        label: const Text('Nueva mesa'),
      ),

      body: Column(
        children: [
          if (uid != null) _BalancePanel(uid: uid),
          const Divider(height: 1),

          // === Lista de movimientos (últimos 10) ===
          if (uid != null)
            SizedBox(
              height: 220,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db
                    .collection('balances')
                    .doc(uid)
                    .collection('movements')
                    .orderBy('ts', descending: true)
                    .limit(10)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('Sin movimientos aún.'));
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = docs[i].data();
                      final type = (m['type'] ?? '').toString().toUpperCase();
                      final amount = (m['amount'] as num?)?.toDouble() ?? 0;
                      final before = (m['before'] as num?)?.toDouble() ?? 0;
                      final after = (m['after'] as num?)?.toDouble() ?? 0;
                      final ts = (m['ts'] as Timestamp?)?.toDate();

                      IconData icon;
                      switch (type) {
                        case 'DEPOSIT':
                          icon = Icons.south_west; break;
                        case 'WITHDRAW':
                          icon = Icons.north_east; break;
                        case 'WIN':
                          icon = Icons.emoji_events; break;
                        case 'LOSS':
                          icon = Icons.cancel_outlined; break;
                        default:
                          icon = Icons.lock_clock; // LOCK_JOIN
                      }

                      final title = switch (type) {
                        'DEPOSIT' => 'Depósito',
                        'WITHDRAW' => 'Retiro',
                        'LOCK_JOIN' => 'Apuesta bloqueada',
                        'WIN' => 'Ganaste',
                        'LOSS' => 'Perdiste',
                        _ => type
                      };

                      return ListTile(
                        dense: true,
                        leading: Icon(icon),
                        title: Text('$title: ${_fmt(amount)}'),
                        subtitle: Text(
                          'Antes: ${_fmt(before)}  →  Después: ${_fmt(after)}'
                          '${ts != null ? ' · ${ts.toLocal()}' : ''}',
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          const Divider(height: 1),

          // === Lista de Mesas (sin cuotas) ===
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('Mesas')
                  .orderBy(FieldPath.documentId) // sin paréntesis en este SDK
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No hay mesas abiertas'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final mesaDocId = docs[i].id;

                    final id = '${data['id'] ?? mesaDocId}';
                    final monto = (data['monto'] as num?)?.toDouble() ?? 0.0;
                    final estado = (data['estado'] ?? 'abierta').toString();

                    final jug = Map<String, dynamic>.from(data['jugadores'] ?? {});
                    final playersInfo = '${jug.length}/2';

                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    final yaEstoy = uid != null && jug[uid] == true;
                    final mesaLlena = jug.length >= 2;
                    final abierta = estado == 'abierta';
                    final puedeUnirse = uid != null && abierta && !yaEstoy && !mesaLlena;

                    // Detectar rival (si 2/2 y estoy dentro)
                    String? rivalUid;
                    if (yaEstoy && jug.length == 2) {
                      for (final k in jug.keys) {
                        if (k != uid) rivalUid = k;
                      }
                    }

                    return ListTile(
                      title: Text('Mesa #$id · Apuesta: ${_fmt(monto)} · Jugadores: $playersInfo'),
                      subtitle: Text('Estado: $estado'),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Botón Unirse
                          ElevatedButton(
                            onPressed: puedeUnirse
                                ? () => _joinMesa(uid: uid!, mesaDocId: mesaDocId, monto: monto)
                                : null,
                            child: Text(
                              yaEstoy
                                  ? 'Ya estás'
                                  : mesaLlena
                                      ? 'Llena'
                                      : !abierta
                                          ? 'Cerrada'
                                          : 'Unirse (${_fmt(monto)})',
                            ),
                          ),
                          // Botones Finalizar (solo si estoy en mesa y estado en_curso y tengo rival)
                          if (estado == 'en_curso' && yaEstoy && rivalUid != null) ...[
                            OutlinedButton(
                              onPressed: () => _finalizarMesa(
                                mesaDocId: mesaDocId,
                                monto: monto,
                                winnerUid: uid!,
                                loserUid: rivalUid!,
                              ),
                              child: const Text('Gano yo'),
                            ),
                            OutlinedButton(
                              onPressed: () => _finalizarMesa(
                                mesaDocId: mesaDocId,
                                monto: monto,
                                winnerUid: rivalUid!,
                                loserUid: uid!,
                              ),
                              child: const Text('Gana rival'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Crear mesa demo (sin cuotas) ----
  Future<void> _crearMesaDemo() async {
    final id = 'mesa${DateTime.now().millisecondsSinceEpoch % 100000}';
    await _db.collection('Mesas').doc(id).set({
      'id': id,
      'monto': 1000,
      'estado': 'abierta',
      'jugadores': <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Mesa creada: #$id')),
    );
  }

  // ---- Unirse a mesa: descuenta available -> locked y te agrega a jugadores.{uid} ----
  Future<void> _joinMesa({
    required String uid,
    required String mesaDocId,
    required double monto,
  }) async {
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La mesa no tiene monto válido')),
      );
      return;
    }

    final balRef = _db.collection('balances').doc(uid);
    final mesaRef = _db.collection('Mesas').doc(mesaDocId);

    double beforeAvail = 0, afterAvail = 0, beforeLocked = 0, afterLocked = 0;
    bool jugadoresCompletos = false;

    try {
      await _db.runTransaction((tx) async {
        // Balance
        final balSnap = await tx.get(balRef);
        final balData = (balSnap.data() ?? {}) as Map<String, dynamic>;
        final available = (balData['available'] as num?)?.toDouble() ?? 0.0;
        final locked = (balData['locked'] as num?)?.toDouble() ?? 0.0;

        if (available < monto) {
          throw Exception('INSUFFICIENT_FUNDS');
        }

        // Mesa
        final mesaSnap = await tx.get(mesaRef);
        if (!mesaSnap.exists) {
          throw Exception('MESA_NO_EXISTE');
        }
        final mesaData = (mesaSnap.data() ?? {}) as Map<String, dynamic>;
        final estado = (mesaData['estado'] ?? 'abierta').toString();
        final jug = Map<String, dynamic>.from(mesaData['jugadores'] ?? {});

        if (estado != 'abierta') throw Exception('MESA_CERRADA');
        if (jug[uid] == true) throw Exception('YA_ESTAS_EN_MESA');
        if (jug.length >= 2) throw Exception('MESA_LLENA');

        // Actualizar balances
        beforeAvail = available;
        beforeLocked = locked;
        afterAvail = available - monto;
        afterLocked = locked + monto;
        tx.update(balRef, {'available': afterAvail, 'locked': afterLocked});

        // Preparar update a la mesa: me sumo + timestamp
        final updateMesa = <String, dynamic>{
          'jugadores.$uid': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Si con mi ingreso quedamos 2/2, pasar a en_curso
        if (jug.length + 1 == 2) {
          updateMesa['estado'] = 'en_curso';
          jugadoresCompletos = true;
        }

        tx.update(mesaRef, updateMesa);
      });

      // Log movimiento de bloqueo (apuesta)
      await _BalancePanel._logMovement(
        uid: uid,
        type: 'LOCK_JOIN',
        amount: monto,
        before: beforeAvail,
        after: afterAvail,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            jugadoresCompletos
                ? 'Te uniste y la mesa comenzó (2/2). Bloqueado: ${_fmt(monto)}'
                : 'Te uniste a la mesa. Bloqueado: ${_fmt(monto)}',
          ),
        ),
      );
    } catch (e) {
      final msg = e.toString();
      String pretty = 'Error al unirse a la mesa';
      if (msg.contains('INSUFFICIENT_FUNDS')) pretty = 'Saldo insuficiente';
      if (msg.contains('MESA_CERRADA')) pretty = 'La mesa está cerrada';
      if (msg.contains('YA_ESTAS_EN_MESA')) pretty = 'Ya estás en esta mesa';
      if (msg.contains('MESA_LLENA')) pretty = 'La mesa ya está completa (2/2)';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pretty)));
    }
  }

  // ---- Finalizar partida: transfiere pozo al ganador y finaliza mesa ----
  Future<void> _finalizarMesa({
    required String mesaDocId,
    required double monto,
    required String winnerUid,
    required String loserUid,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final mesaRef = _db.collection('Mesas').doc(mesaDocId);
    final winRef = _db.collection('balances').doc(winnerUid);
    final loseRef = _db.collection('balances').doc(loserUid);

    double winBeforeAvail = 0, winAfterAvail = 0;
    double loseBeforeAvail = 0, loseAfterAvail = 0;

    try {
      await _db.runTransaction((tx) async {
        // Mesa
        final mesaSnap = await tx.get(mesaRef);
        if (!mesaSnap.exists) throw Exception('MESA_NO_EXISTE');
        final mesaData = mesaSnap.data() as Map<String, dynamic>;
        final estado = (mesaData['estado'] ?? 'abierta').toString();
        final jug = Map<String, dynamic>.from(mesaData['jugadores'] ?? {});
        if (estado != 'en_curso') throw Exception('MESA_NO_EN_CURSO');
        if (!(jug[winnerUid] == true && jug[loserUid] == true)) {
          throw Exception('JUGADORES_INVALIDOS');
        }

        // Balances
        final winSnap = await tx.get(winRef);
        final loseSnap = await tx.get(loseRef);
        final winData = (winSnap.data() ?? {}) as Map<String, dynamic>;
        final loseData = (loseSnap.data() ?? {}) as Map<String, dynamic>;

        final wAvail = (winData['available'] as num?)?.toDouble() ?? 0.0;
        final wLocked = (winData['locked'] as num?)?.toDouble() ?? 0.0;
        final lAvail = (loseData['available'] as num?)?.toDouble() ?? 0.0;
        final lLocked = (loseData['locked'] as num?)?.toDouble() ?? 0.0;

        if (wLocked < monto || lLocked < monto) {
          throw Exception('LOCK_INSUFICIENTE');
        }

        // Transferencia de pozo (2 * monto):
        winBeforeAvail = wAvail;
        loseBeforeAvail = lAvail;

        final newWAvail = wAvail + wLocked + lLocked;
        final newWLocked = wLocked - monto;
        final newLAvail = lAvail;
        final newLLocked = lLocked - monto;

        winAfterAvail = newWAvail;
        loseAfterAvail = newLAvail;

        tx.update(winRef, {'available': newWAvail, 'locked': newWLocked});
        tx.update(loseRef, {'available': newLAvail, 'locked': newLLocked});

        // Finalizar mesa
        tx.update(mesaRef, {
          'estado': 'finalizada',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // Logs
      await _BalancePanel._logMovement(
        uid: winnerUid,
        type: 'WIN',
        amount: monto,
        before: winBeforeAvail,
        after: winAfterAvail,
      );
      await _BalancePanel._logMovement(
        uid: loserUid,
        type: 'LOSS',
        amount: monto,
        before: loseBeforeAvail,
        after: loseAfterAvail,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partida finalizada')),
      );
    } catch (e) {
      String pretty = 'No se pudo finalizar la partida';
      final msg = e.toString();
      if (msg.contains('MESA_NO_EN_CURSO')) pretty = 'La mesa no está en curso';
      if (msg.contains('LOCK_INSUFICIENTE')) pretty = 'Algún jugador no tiene locked suficiente';
      if (msg.contains('JUGADORES_INVALIDOS')) pretty = 'Jugadores inválidos para esta mesa';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pretty)));
    }
  }
}

/// Panel superior que muestra el saldo del usuario y permite operar
class _BalancePanel extends StatelessWidget {
  final String uid;
  const _BalancePanel({required this.uid});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('balances').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        final data = snap.data?.data();
        final available = (data?['available'] as num?)?.toDouble() ?? 0;
        final locked = (data?['locked'] as num?)?.toDouble() ?? 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Disponible: ${_fmt(available)}   ·   Bloqueado: ${_fmt(locked)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final amount = await _promptAmount(context, title: 'Depositar');
                  if (amount == null) return;
                  await _deposit(context, uid: uid, amount: amount);
                },
                child: const Text('Depositar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final amount = await _promptAmount(context, title: 'Retirar');
                  if (amount == null) return;
                  await _withdraw(context, uid: uid, amount: amount);
                },
                child: const Text('Retirar'),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<double?> _promptAmount(BuildContext context, {required String title}) async {
    final controller = TextEditingController();
    return showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Monto (ej: 1000)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text.replaceAll(',', '.'));
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Ingrese un monto válido > 0')),
                );
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  static Future<void> _logMovement({
    required String uid,
    required String type, // 'DEPOSIT' | 'WITHDRAW' | 'LOCK_JOIN' | 'WIN' | 'LOSS'
    required double amount,
    required double before,
    required double after,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('balances')
        .doc(uid)
        .collection('movements');

    await ref.add({
      'type': type,
      'amount': amount,
      'before': before,
      'after': after,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> _deposit(BuildContext context, {required String uid, required double amount}) async {
    final ref = FirebaseFirestore.instance.collection('balances').doc(uid);

    double before = 0, after = 0;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = (snap.data() ?? {}) as Map<String, dynamic>;
      before = (data['available'] as num?)?.toDouble() ?? 0;
      after = before + amount;
      tx.set(ref, {'available': after}, SetOptions(merge: true));
    });

    await _logMovement(uid: uid, type: 'DEPOSIT', amount: amount, before: before, after: after);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Depósito realizado: ${amount.toStringAsFixed(0)}')),
    );
  }

  static Future<void> _withdraw(BuildContext context, {required String uid, required double amount}) async {
    final ref = FirebaseFirestore.instance.collection('balances').doc(uid);

    final pre = await ref.get();
    final preAvailable = ((pre.data() ?? {})['available'] as num?)?.toDouble() ?? 0;
    if (amount > preAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saldo insuficiente')));
      return;
    }

    double before = 0, after = 0;
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = (snap.data() ?? {}) as Map<String, dynamic>;
        before = (data['available'] as num?)?.toDouble() ?? 0;

        if (amount > before) {
          throw Exception('SALDO_INSUFICIENTE');
        }

        after = before - amount;
        tx.update(ref, {'available': after});
      });

      await _logMovement(uid: uid, type: 'WITHDRAW', amount: amount, before: before, after: after);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retiro realizado: ${amount.toStringAsFixed(0)}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saldo insuficiente')));
    }
  }

  static String _fmt(double? v) => v == null ? '--' : v.toStringAsFixed(0);
}