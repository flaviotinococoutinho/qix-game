class_name ActorLifecycle
extends RefCounted
## Vocabulário comum do elenco. Estados descrevem fatos do domínio; animação só os observa.
## IDs 1 e 2 são reservados ao jogador e Núcleo; os pools atribuem IDs monotônicos a cada spawn.

enum State { DESPAWNED, WARMUP, ACTIVE, DORMANT, DYING }
enum Kind { PLAYER, BOSS, WALKER, DART, EMBER }
enum Capability { MOVE_BOUNDARY = 1, MOVE_FREE = 2, DRAW = 4, CAPTURE = 8, CUT_TRAIL = 16, FOLLOW_TRAIL = 32 }

const PLAYER_ID := 1
const BOSS_ID := 2


## Estase imobiliza o Núcleo; tocar seu corpo continua perigoso.
static func is_collidable(state: int, kind: int = Kind.WALKER) -> bool:
	return state == State.ACTIVE or (kind == Kind.BOSS and state == State.DORMANT)


static func is_visible(state: int) -> bool:
	return state != State.DESPAWNED


static func capabilities(kind: int) -> int:
	match kind:
		Kind.PLAYER: return Capability.MOVE_BOUNDARY | Capability.DRAW | Capability.CAPTURE
		Kind.BOSS: return Capability.MOVE_FREE | Capability.CUT_TRAIL
		Kind.WALKER: return Capability.MOVE_BOUNDARY
		Kind.DART: return Capability.MOVE_FREE | Capability.CUT_TRAIL
		Kind.EMBER: return Capability.FOLLOW_TRAIL
	return 0
