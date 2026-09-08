class_name CoordinateSpace
extends RefCounted
## Único ponto de conversão entre espaços. Nenhuma outra camada mantém offsets próprios.
##
## Espaços:
##  - campo (field): célula inteira, (0,0) = canto superior esquerdo da moldura, 225×283.
##  - tela (screen): pixel lógico no viewport 240×320 retrato.
##  - board histórico: coordenadas da placa (x no eixo de 320, y no eixo de 256), sem rotação.
##    A moldura original ocupa x ∈ [19,301], y ∈ [15,239] (06-gameplay.md §4.4); em retrato o
##    eixo de 320 é vertical e o de 256 (visível 8..247) é horizontal.

const VIEWPORT := Vector2i(240, 320)
## Pixel de tela da célula de campo (0,0): 7 px de margem esquerda (y=15 − 8 visíveis),
## 19 px de HUD acima (x=19 do board).
const FIELD_ORIGIN := Vector2i(7, 19)
const HISTORICAL_FRAME_MIN := Vector2i(19, 15)   # (board_x, board_y)


static func field_to_screen(c: Vector2i) -> Vector2i:
	return FIELD_ORIGIN + c


static func screen_to_field(s: Vector2i) -> Vector2i:
	return s - FIELD_ORIGIN


## board (bx no eixo de 320, by no eixo de 256) → campo.
static func historical_to_field(bx: int, by: int) -> Vector2i:
	return Vector2i(by - HISTORICAL_FRAME_MIN.y, bx - HISTORICAL_FRAME_MIN.x)


static func field_to_historical(c: Vector2i) -> Vector2i:
	return Vector2i(c.y + HISTORICAL_FRAME_MIN.x, c.x + HISTORICAL_FRAME_MIN.y)
