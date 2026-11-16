# Переход DX9-шейдеров движка на VS_3_0

План для этого репозитория. Опорный коммит форка: [alexxstst/TalesOfPirate@258472e](https://github.com/alexxstst/TalesOfPirate/commit/258472e2992e542f696683d99eda4d554ad9a235) (`Update DX9 shaders to vs_3_0 and remove old data`, 2026-04-22).

Цель: DX9-сборка умеет грузить те же вершинные шейдеры из HLSL и компилировать их профилем `vs_3_0`. Старые `.vsh` остаются и выбираются той же сборкой, пока не задана директива `LW_USE_VS30`. Раскладка константных регистров и декларации вершин не меняются, CPU по-прежнему пишет их через `SetVertexShaderConstantF`. Шейдер шрифта остаётся и получает HLSL-вариант рядом с `font.vsh`. Путь DX8 (`LW_USE_DX8`, `shader\dx8\*.vso`, `lwShaderMgr8`) не трогаем.

## Что делает форк и что из этого не переносим

Коммит меняет 93 файла (+738 / −3974). Для перехода нужны только DX9-шейдеры и четыре исходника движка:

| Файл форка | Берём |
|---|---|
| `sources/Engine/src/lwShaderMgr.cpp` | Да. Профиль `vs_3_0` и передача всего массива `D3DXMACRO`. |
| `sources/Engine/src/ShaderLoad.cpp` | Да. 11 static/skin VS и 6 skinmesh VS собираются из двух мастер-HLSL. |
| `sources/Engine/src/MPResManger.cpp` | Частично. Эффекты, shade и minimap переводятся на HLSL. Блок шрифта не удалять. |
| `sources/Engine/include/ShaderLoad.h`, `lwShaderTypes.h`, `MPResManger.h` | Нет. Форк вырезает `VSTU_FONT_E5` и `VDT_EFF_FONT`. Здесь они остаются. |
| `Client/shader/dx9/*.hlsl` (новые) | Да, плюс отдельный `font.hlsl`, которого в форке нет. |
| `Client/shader/dx9/font.vsh`, `font9.vsh` | `font.vsh` оставить: это старый путь без `LW_USE_VS30`. Рядом кладётся `font.hlsl`. `font9.vsh` загрузчик не открывает. |
| `sources/Engine/src/MPMap.cpp`, `MPMap.h`, `MPTile.h` | Нет. Это удаление SkyDoom (`vs_skydoom.vsh` / `ps_skydoom.psh`), к профилю шейдеров не относится. |
| `Client/shader/*.vsh`, `eff.fx`, `renderstate.fx` в корне `Client/shader` | Нет в этом изменении. DX8-сборка читает `shader\dx8\*.vso`. Корневые `.vsh` — исходники для пересборки DX8. |
| `Client/shader/dx9/terrain.hlsl`, `xyz_normal_*.hlsl` | Не грузятся `LoadShader0` / `LoadTotalVShader`. Удаление — отдельная уборка, не часть перехода. |
| `Client/shader/dx9_hlsl/eff1.hlsl` | Дубль `dx9/eff1.hlsl`. Второй каталог не заводить. |
| `server/GameServer/gamedata.sqlite-shm`, `.sqlite-wal` | Мусор коммита. Не переносить. |

В комментарии форка в `MPResManger.cpp` написано «vs_2_0». Это расходится с правкой `lwShaderMgr.cpp`, где профиль уже `vs_3_0`. В этом репозитории цель одна: `vs_3_0`.

## Как устроена загрузка сейчас

Точка входа — `MPRender.cpp`: `LoadShader0`, затем `LoadShader1`, затем `CMPResManger::LoadTotalVShader`.

Каталог шейдеров выбирается в `lwIFunc.cpp`: DX9 → `.\shader\dx9\`.

`lwShaderMgr9::RegisterVertexShader` (`sources/Engine/src/lwShaderMgr.cpp`, около строки 319) читает файл целиком и ветвится по `VS_FILE_*` из `lwITypes.h`:

- `VS_FILE_OBJECT` (1) — сырой байткод;
- `VS_FILE_ASM` (2) — `D3DXAssembleShader`;
- `VS_FILE_HLSL` (3) — `D3DXCompileShader`.

Сейчас все DX9-шейдеры регистрируются как `VS_FILE_ASM`. Ветка HLSL в этом репозитории фактически не используется и сломана:

- без `LW_SHADER_DEBUG_VS` (дефайн закомментирован в `lwDirectX.h`) профиль `"vs_2_0"`, а в компилятор уходит одна макропара `D3DXMACRO macro = {defines->Name, defines->Definition}` без терминатора `{NULL, NULL}`. При `defines == NULL` это чтение по нулевому указателю;
- с `LW_SHADER_DEBUG_VS` профиль `"vs_1_1"`, макросы не передаются (`NULL`), файл компилируется повторно через `D3DXCompileShaderFromFile`;
- `ID3DXBuffer* buf_error` при ошибке отпускается и никуда не пишется. `LoadShader0` просто делает `goto __ret`.

Часть `.vsh` в `Client/shader/dx9` — это уже листинг `fxc /Tvs_2_a`, а не рукописный vs_1_1 (`skinmesh8_*_tt*.vsh`, `vs_pndt0*.vsh`, `vs_pnt0*.vsh`). Рукописный vs_1_1: `pu4nt0_ld.vsh`, `pb1u4nt0_ld.vsh`, `pb2u4nt0_ld.vsh`, `pb3u4nt0_ld.vsh`, `eff1..4.vsh`, `shadeeff.vsh`, `minimap.vsh`, `font.vsh`. `eff2.vsh` помечен как `vs.1.0`. Сборка всё равно прогоняет их через ассемблер, поэтому профиль записан внутри текста шейдера, а не в C++.

## Контракт, который нельзя сдвинуть

CPU не читает таблицу констант HLSL для рабочих мешей. Константы пишет `lwxRenderCtrlVSVertexBlend_dx8::BeginSet` / `BeginSetSubset` абсолютными индексами (`lwxRenderCtrlVS.h`):

| Регистр | Имя в коде | Содержимое |
|---|---|---|
| c0 | `VS_CONST_REG_BASE` | `(1, 0, 0, 765.01)`. `.x` — единица для остаточного веса и клампа света. `.z` — specular (чёрный). `.w` — масштаб индекса кости. |
| c1..c4 | `VS_CONST_REG_VIEWPROJ` | Для скининга: уже перемноженные world * viewProj, **транспонированные** перед записью. |
| c5 | `VS_CONST_REG_LIGHT_DIR` | Направление света. |
| c6..c7 | `VS_CONST_REG_LIGHT_AMB` / `DIF` | Ambient и diffuse материала. |
| c8 | `VS_CONST_REG_TS0_UVMAT` | UV-матрица стадии 0, 4 регистра, транспонированная. |
| c12 | `VS_CONST_REG_TS1_UVMAT` | Стадия 1. |
| c16 | `VS_CONST_REG_TS2_UVMAT` | Стадия 2. |
| c21 | `VS_CONST_REG_MAT_PALETTE` | Палитра костей, 3 регистра `float4` на кость, до 50 костей в буфере CPU (`bone_num * 3`). |

`c0.w = 765.01` — это `3 * 255 + 0.01`, а не «stride = 3». `D3DDECLTYPE_D3DCOLOR` приходит в шейдер как float 0..1 (`byte/255`). Умножение на 765.01 и усечение до int даёт `byte * 3`, то есть номер первого регистра кости. Комментарий форка «stride = 3» этому не соответствует. В HLSL оставить `idx = (int)(blendIndex * Base.w)`. Не подставлять литерал 3: на D3DCOLOR это даст индекс 0 для любой кости, кроме 255.

Матрицы CPU кладёт построчно после `lwMatrix44Transpose`. В HLSL матрица по умолчанию column-major, и `mul(vector, matrix)` совпадает с `dp4` по строкам cN..cN+3. Индексация `World[0]..World[3]` соберёт колонки и перепутает матрицу. Форк это уже оговорил в `skinmesh.hlsl` / `static_skin.hlsl`. Повторить тот же `mul(v, World)`.

Второй контроллер, `lwxRenderCtrlVSVertexBlend` (тип `RENDERCTRL_VS_VERTEXBLEND_DX9`), ходит в константы по именам `blend_num`, `mat_viewproj`, `light_dir`, `mat_bonepallette` через `ID3DXConstantTable`. Таблицу он достаёт `D3DXGetShaderConstantTable` из байткода. Текущие ASM-шейдеры и форк под эти имена не написаны. Переход их не переименовывает и этот контроллер не переключает. Явные `register(cN)` обязательны: иначе компилятор разложит константы сам, и запись `dx8`-контроллера попадёт не туда.

Семейство `vs_pndt0` (нескиновые статические меши) живёт в другой раскладке. Её задаёт заголовок уже скомпилированного `vs_pndt0_ld_t0uvmat.vsh`, а не enum выше:

| Регистр | Содержимое |
|---|---|
| c0..c3 | World * ViewProj |
| c4 | LightDir |
| c5 | Ambient |
| c7..c8 | UVMatrix0, `float4x3` (две строки). c6 в текущем листинге занят литералом `def c6, 0, 1, 0, 0`. |

CPU для UV-анимации пишет 4 регистра с c8 (`VS_CONST_REG_TS0_UVMAT`). Шейдер читает c7 и c8. Это уже так в поставке vs_2_x. HLSL должен повторить `register(c7)` / `register(c8)`, а не «починить» сдвиг на c8 в том же изменении. Проверка скролля текстуры на статическом меше покажет, регрессия это или старое поведение.

Скиновая UV-матрица в `skinmesh8_*` сидит на c12 (стадия 1 в enum), не на c8. Так же в листинге fxc (`Texture c12`). Не выравнивать её на `VS_CONST_REG_TS0_UVMAT`.

Эффекты, shade, minimap и шрифт пишут регистры сами, из `CMPResManger` / `MPFont` / `SMallMap`, и не через render-ctrl:

| | c0..c3 | c4..c7 | c8 | дальше |
|---|---|---|---|---|
| eff1, eff3, eff4 | World | ViewProj | цвет | `UVs[4]` с c9, индекс — `BLENDINDICES` |
| eff2 | то же | то же | цвет | UV из вершинного `TEXCOORD0`, массив не нужен |
| shadeeff | не используется (в ASM `m4x4` по c0 закомментирован) | ViewProj | цвет | с c9 чередование UV, Pos, UV, Pos… Индекс в `TEXCOORD1` — **абсолютный** номер регистра |
| minimap | World | ViewProj | цвет | `Positions[4]` с c9, индекс 0..3 в `BLENDWEIGHT`, UV из `TEXCOORD0` |
| font | World | ViewProj | цвет | с c9 пары Pos, UV, Pos, UV… Индекс в `BLENDWEIGHT` — 0, 2, 4, 6 |

`vs_3_0` можно ставить только вместе с `ps_3_0` или с выключенным пиксельным шейдером (`SetPixelShader(NULL)`, фиксированный конвейер). Сейчас пиксельный шейдер в движке ставит только мёртвый путь SkyDoom. Пока его не включают, связка `vs_3_0` + fixed-function законна. Нельзя позже подвязать к этим VS старые `ps_1_x` / `ps_2_0`.

`vs_3_0` требует вершинную декларацию. FVF при активном VS_3_0 не работает. Пути, которые уже делают `SetVertexDeclaration` (меши, эффекты, шрифт, minimap), совместимы. Пути с `SetFVF` + `SetVertexShader(NULL)` (экранный текст при `DRAWONCE`) шейдер не используют, их не переписывать.

Железо нового пути: Shader Model 3.0. Текущие `vs_2_x` живут на SM2, поэтому проверка `Caps.VertexShaderVersion >= D3DVS_VERSION(3, 0)` включается только при `LW_USE_VS30` (см. ниже). `CreateVertexShader` на SM2 просто вернёт `E_FAIL`, и без этой проверки ошибка утонет в пустом `goto __ret`.

## Переключение старых и новых шейдеров

Оба набора живут на диске. Какой из них регистрируется, решает одна директива компиляции движка, не рантайм и не второй набор слотов `VST_*`.

Загрузчик уже умеет оба формата: `RegisterVertexShader` ветвится по `VS_FILE_ASM` и `VS_FILE_HLSL`. Регистры, декларации, `MPFont.cpp`, render-ctrl и индексы `_vecVDecl` от профиля не зависят. Поэтому директива меняет только таблицы «имя файла + флаг + макросы» и профиль в HLSL-ветке компилятора.

Директива: `LW_USE_VS30`. На реализации её добавляют в `sources/Engine/include/lwDirectX.h`, внутри `#if (defined LW_USE_DX9)`, сразу над `LW_SHADER_DEBUG_VS`, закомментированной по умолчанию — так же, как сейчас лежит `LW_SHADER_DEBUG_VS`. Пока строки нет или она закомментирована, DX9-сборка ведёт себя как сейчас. В код её не вносят, пока не готовы таблицы `#if` и сами HLSL.

В `.cpp` её ставить нельзя. `#define` в `ShaderLoad.cpp` не виден `MPResManger.cpp`, а `#define` в `lwShaderMgr.cpp` не виден ни одному загрузчику. Переключать надо три единицы трансляции сразу: таблицы в `ShaderLoad.cpp` и в DX9-ветке `MPResManger.cpp`, плюс профиль HLSL в `lwShaderMgr.cpp`. Все три включают `stdafx.h`, а тот через `GlobalInc.h` тянет `lwDirectX.h`. `MPResManger.cpp` подключает `GlobalInc.h` ещё и напрямую. `LW_USE_DX9` живёт в том же заголовке, поэтому DX8-сборка этот дефайн не увидит даже если строку раскомментировать по ошибке вне блока DX9.

В препроцессор `MindPower3D.vcxproj` её не выносить. Включение и откат — раскомментировать или закомментировать одну строку и пересобрать движок. Клиентский проект не трогать.

Без `LW_USE_VS30`:

- `LoadShader0` — нынешние 11 `.vsh`, флаг `VS_FILE_ASM`, старый массив `defines` ассемблером не читается;
- `LoadShader1` — шесть `skinmesh8_*_tt*.vsh`, `VS_FILE_ASM`;
- DX9-ветка `LoadTotalVShader` — `eff1..4.vsh`, `font.vsh`, `shadeeff.vsh`, `minimap.vsh`, `VS_FILE_ASM`.

С `LW_USE_VS30` те же слоты `VST_*` / `VSTU_*` и те же декларации, другие файлы и флаг `VS_FILE_HLSL`:

- `LoadShader0` — `static_skin.hlsl` (4 раза) и `vs_pndt0.hlsl` (7 раз), у каждой записи свой `D3DXMACRO[]` с `{NULL, NULL}`;
- `LoadShader1` — `skinmesh.hlsl` шесть раз, пары `NUM_SKIN_WEIGHTS` / `TT_MODE`;
- `LoadTotalVShader` — `eff1..4.hlsl`, `font.hlsl`, `shadeeff.hlsl`, `minimap.hlsl`. Слот `i == 4` по-прежнему `VSTU_FONT_E5` → `_dwFontVS`. Меняется только имя файла и флаг.

Каркас в каждом из трёх мест:

```cpp
#if defined(LW_USE_VS30)
    static const char* shader_file[] = { /* .hlsl, несколько слотов на один мастер */ };
    static const D3DXMACRO* defines_tab[] = { /* по массиву на слот, терминатор {NULL, NULL} */ };
    const DWORD file_flag = VS_FILE_HLSL;
#else
    static const char* shader_file[] = { /* нынешние .vsh, один файл на слот */ };
    const DWORD file_flag = VS_FILE_ASM;
#endif

shader_mgr->RegisterVertexShader(shader_type[i], path, file_flag, defines_для_слота);
```

В ASM-ветке четвёртый аргумент можно оставить как сейчас (`&defines[i]` в `LoadShader0`, его отсутствие в `LoadShader1` и в `LoadTotalVShader`). Ассемблер макросы не применяет. В HLSL-ветке указатель обязан быть либо `NULL`, либо началом массива, заканчивающегося `{NULL, NULL}`. Один общий `defines[]` на все 11 слотов, как сейчас, для мастеров не годится: у соседних слотов разные дефайны.

`OnResetDevice` файлы не открывает, только заново берёт уже зарегистрированные шейдеры по `VSTU_*`. Под директиву его не оборачивать.

Проверка капсов `VertexShaderVersion >= D3DVS_VERSION(3, 0)` включается только вместе с `LW_USE_VS30`. Сборка без директивы по-прежнему принимает SM2, потому что старые листинги — `vs_1_1` / `vs_2_x`.

Сравнивать кадры двумя пересборками движка: с закомментированным `LW_USE_VS30` и с раскомментированным. Откат — снова закомментировать строку в `lwDirectX.h`. Файлы шейдеров при этом не трогать.

`.vsh` в `Client/shader/dx9` после перехода не удалять. Они и есть старый путь. `font.hlsl` лежит рядом с `font.vsh`. Корневые `Client/shader/*.vsh` и `shader\dx8` к этой директиве не относятся.

## Шаг 1. Компилятор в `lwShaderMgr9`

Обе ветки HLSL (`LW_SHADER_DEBUG_VS` и обычная) перевести на `"vs_3_0"`.

В обе ветки передавать исходный указатель `defines`, если он не `NULL` и `defines->Name != NULL`. Массив обязан заканчиваться `{NULL, NULL}`. Одна скопированная макропара, как сейчас, недостаточна: skinmesh задаёт два дефайна сразу.

При ошибке писать текст `buf_error` в лог (`LG` / `OutputDebugString`) и в `MessageBox` вместе с путём файла. Иначе первый же несовпавший семантик придётся искать вслепую.

`RegisterVertexShader` по-прежнему не сохраняет `ID3DXConstantTable` (последний аргумент `D3DXCompileShader` — `NULL`). Так и оставить.

Сигнатуру `RegisterVertexShader(..., const D3DXMACRO* defines = NULL)` не менять. DX8-менеджер другой класс, его этот метод не касается.

## Шаг 2. `LoadShader0` — статические и жёсткие скины

Сейчас 11 файлов, все `VS_FILE_ASM`. Макросы `NUM_SKIN_WEIGHTS` в массив передаются, но ассемблер их игнорирует. Заменить на схему форка.

Четыре скина, один файл `static_skin.hlsl`, дефайн `NUM_EXPLICIT_WEIGHTS`:

| Тип | Было | Дефайн | Вершины (`ShaderLoad.cpp`, `ve0..ve3`) |
|---|---|---|---|
| `VST_PU4NT0_LD` | `pu4nt0_ld.vsh` | 0 | pos, blendindices (D3DCOLOR), normal, uv. Веса нет. |
| `VST_PB1U4NT0_LD` | `pb1u4nt0_ld.vsh` | 1 | + `BLENDWEIGHT` float1 |
| `VST_PB2U4NT0_LD` | `pb2u4nt0_ld.vsh` | 2 | + `BLENDWEIGHT` float2 |
| `VST_PB3U4NT0_LD` | `pb3u4nt0_ld.vsh` | 3 | + `BLENDWEIGHT` float3 |

Последний вес = `c0.x - sum(явные)`. Индексы костей из D3DCOLOR в ASM читаются как `v2.zyxw`: первая кость — `.z`, затем `.y`, `.x`, `.w`. HLSL форка повторяет это полями `boneIndices.z/y/x/w`. Не «исправлять» на `.xyzw`.

Семь нескиновых VS, один файл `vs_pndt0.hlsl`:

| Тип | Было | Дефайны |
|---|---|---|
| `VST_PNT0_LD_TT0` | `vs_pnt0_ld_t0uvmat.vsh` | `USE_TEX_TRANSFORM`, `NO_DIFFUSE` |
| `VST_PNT0_TT0` | `vs_pnt0_t0uvmat.vsh` | `NO_LIGHTING`, `USE_TEX_TRANSFORM`, `NO_DIFFUSE` |
| `VST_PNDT0_LD_TT0` | `vs_pndt0_ld_t0uvmat.vsh` | `USE_TEX_TRANSFORM` |
| `VST_PNT0_LD` | `vs_pnt0_ld.vsh` | `NO_DIFFUSE` |
| `VST_PNDT0` | `vs_pndt0.vsh` | `NO_LIGHTING` |
| `VST_PNDT0_LD` | `vs_pndt0_ld.vsh` | нет (только `{NULL,NULL}`) |
| `VST_PNDT0_TT0` | `vs_pndt0_t0uvmat.vsh` | `NO_LIGHTING`, `USE_TEX_TRANSFORM` |

`NO_LIGHTING` убирает normal из входа. `NO_DIFFUSE` убирает `COLOR0`. Это совпадает с декларациями `vepnt0` / `vepndt0`: у `VDT_PNT0` нет цвета, у `VDT_PNDT0` цвет есть. Декларации в `LoadShader0` не менять. Каждый набор макросов — отдельный `static const D3DXMACRO[]` с терминатором, в `RegisterVertexShader` передаётся `defines_tab[i]`, флаг `VS_FILE_HLSL`.

В варианте `NO_LIGHTING` + `NO_DIFFUSE` текущий ASM пишет в diffuse константу (в листинге это не ноль). Форк ставит `float4(1, 0, 0, 0)`. Сверить с конкретным `.vsh` (`vs_pnt0_t0uvmat.vsh`) до копирования этой строки: если там `mov oD0, c4.x` и c4 в этом варианте не свет, а единица, оставить то же значение, которое реально лежит в регистре на кадре.

Декларации `VDT_*` и цикл их регистрации не трогать.

## Шаг 3. `LoadShader1` — анимированный skinmesh

`UserShaderType` в `ShaderLoad.h` объявляет 12 слотов (`VSTU_SKINMESH0..3` × TT1..TT3). Цикл грузит только первые 6, и это 1-weight и 2-weight. Слоты 2 и 3 (три и четыре веса) пустые и в форке тоже пустые. Цикл оставить `i < 6`. Не раздувать его до `shader_num`: массив имён станет короче 12.

Один файл `skinmesh.hlsl`, два дефайна:

| Индекс цикла | Тип | `NUM_SKIN_WEIGHTS` | `TT_MODE` | Было |
|---|---|---|---|---|
| 0 | `VSTU_SKINMESH0_TT1` | 1 | 1 | `skinmesh8_1_tt1.vsh` |
| 1 | `VSTU_SKINMESH1_TT1` | 2 | 1 | `skinmesh8_2_tt1.vsh` |
| 2 | `VSTU_SKINMESH0_TT2` | 1 | 2 | `skinmesh8_1_tt2.vsh` |
| 3 | `VSTU_SKINMESH1_TT2` | 2 | 2 | `skinmesh8_2_tt2.vsh` |
| 4 | `VSTU_SKINMESH0_TT3` | 1 | 3 | `skinmesh8_1_tt3.vsh` |
| 5 | `VSTU_SKINMESH1_TT3` | 2 | 3 | `skinmesh8_2_tt3.vsh` |

Поведение, которое надо сохранить по листингу fxc и по HLSL форка:

- 1 вес: кость одна, `boneIndices.x * c0.w`. Веса во входе нет.
- 2 веса: `w1 = weight.x`, `w2 = c0.x - weight.x - weight.y`. В ASM 2-weight это `add r0.x, -r0.x, c0.x` после сложения обеих компонент веса. Индексы — `.x` и `.y`, не свизл `zyxw` статического скина. У `skinmesh8_2_tt1.vsh` свизл индекса `v2.xyyw`.
- TT1: `oT0 = uv`, `oT1 = Texture * uvh`, матрица на c12..c15.
- TT2: `oT0 = uv`, `oT1 = uv`, `oT2 = Texture2 * uvh`, матрица на c16..c19.
- TT3: как TT2 плюс `oT3 = uv`.
- `uvh = (u, v, 1, v)`.
- Палитра `float4 BV[75] : register(c21)` — 25 костей × 3 строки. CPU умеет записать до 50 костей × 3 = 150 регистров, но шейдер адресует 75. Это предел текущих `.vsh`. Не расширять массив в этом переходе: лишние кости и раньше не читались.
- Свет: `lit(NdotL, 0, 0)`, `diffuse = min(L.y * Diffuse + Ambient, c0.x)`, `specular = c0.z`.

`skinmesh8_2_fog.vsh` загрузчиком не читается. Не переносить и не удалять в этом изменении.

## Шаг 4. `LoadTotalVShader` — эффекты, shade, minimap, шрифт

DX9-ветка `CMPResManger::LoadTotalVShader(lwISysGraphics*)` сейчас грузит 7 ASM. Порядок и индексы `_vecVDecl` зафиксированы вызовами `GetShadeVDecl()` → `[5]`, `GetFontVDecl()` → `[4]`, `GetMinimapVDecl()` → `[6]`. Форк удалил шрифт и сдвинул shade на `[4]`, minimap на `[5]`. Здесь сдвиг не делать.

Оставить массив из 7 элементов:

| i | Тип | Декларация | Файл | Флаг |
|---|---|---|---|---|
| 0 | `VSTU_EFFECT_E1` | `VDT_EFF_134`, `ve_dec_effect1` | `eff1.hlsl` | `VS_FILE_HLSL` |
| 1 | `VSTU_EFFECT_E2` | `VDT_EFF_2`, `ve_dec_effect2` | `eff2.hlsl` | `VS_FILE_HLSL` |
| 2 | `VSTU_EFFECT_E3` | `VDT_EFF_134` | `eff3.hlsl` | `VS_FILE_HLSL` |
| 3 | `VSTU_EFFECT_E4` | `VDT_EFF_134` | `eff4.hlsl` | `VS_FILE_HLSL` |
| 4 | `VSTU_FONT_E5` | `VDT_EFF_FONT`, `ve_dec_font` | `font.hlsl` | `VS_FILE_HLSL` |
| 5 | `VSTU_SHADE_E6` | `VDT_EFF_SHADE`, `ve_dec_shade` | `shadeeff.hlsl` | `VS_FILE_HLSL` |
| 6 | `VSTU_MINIMAP_E6` | `VDT_EFF_MINIMAP`, `ve_dec_map` | `minimap.hlsl` | `VS_FILE_HLSL` |

Сохранить присвоения:

- `i < 4` → `_vecVShader`;
- `i == 4` → `_dwFontVS`;
- `i == 5` → `_dwShadeMapVS`;
- `i == 6` → `_dwMinimapVS`.

То же в `OnResetDevice`: список из 7 типов, включая `VSTU_FONT_E5` и `VDT_EFF_FONT`. Форк сократил его до 6.

Не трогать:

- `GetFontVS` / `GetFontVDecl` и поле `_dwFontVS` в `MPResManger.h`;
- `VSTU_FONT_E5` в `ShaderLoad.h`;
- `VDT_EFF_FONT` в `lwShaderTypes.h`;
- DX8-ветку `LoadTotalVShader`, которая грузит `font.vso` и `dwDecFont`.

`eff1.hlsl` и `eff3.hlsl` / `eff4.hlsl` по ASM одинаковы (позиция × world × viewproj, цвет из c8, UV из `c[blendindices + 9]`). Отдельные файлы нужны, потому что это разные объекты `IDirect3DVertexShader9` и разные слоты `VSTU_*`. Можно включить общий `.hlsli`, но регистрация всё равно по трём путям.

`eff2.hlsl` UV из вершины не индексирует. Декларация `ve_dec_effect2` при этом совпадает с effect1 (есть `BLENDINDICES`, нет `TEXCOORD`). Шейдер `eff2.vsh` объявляет `dcl_texcoord0`, а не `dcl_blendindices`. Расхождение декларации и ASM уже есть. При компиляции HLSL вход `TEXCOORD0` при декларации без texcoord даст мусор или ошибку на draw. Перед заменой снять один кадр эффекта типа 2: если UV живые, декларацию `ve_dec_effect2` надо дополнить `TEXCOORD0` в том же изменении, что и HLSL. Если эффект 2 фактически не использует UV из потока, оставить вход как в ASM и не выдумывать семантику. Это единственное место, где декларацию, возможно, придётся поправить, и только по результату проверки.

`shadeeff.hlsl`: позиция и UV не в вершине. `TEXCOORD1.xy` — абсолютные номера регистров (9, 11, 13… для UV и 10, 12, 14… для позиции). В HLSL `Data[240] : register(c9)`, индекс в массиве = `регистр - 9`. Потолок vs_3_0 — 256 float4-констант, от c9 свободно 247 слотов. 240 — запас форка под сетку shade. Не увеличивать.

`minimap.hlsl`: индекс 0..3 в `BLENDWEIGHT`, позиция из `Positions[4]` на c9..c12, UV из вершины. Совпадает с `minimap.vsh` (`c[a0.x + 9]`, `mov oT0.xy, v7`).

Старый путь `LoadTotalVShader()` без `sys_graphics` (сборка `font.vsh` через `D3DXAssembleShaderFromFile` около строки 1516) — DX8/legacy. Если DX9-сборка его не вызывает, не переписывать. Если вызывает, он тоже должен грузить `font.hlsl` через менеджер, а не второй ассемблер. Проверить по call graph от `CMPResManger::LoadTotalRes` перед правкой: DX9-инициализация из `MPRender.cpp` идёт в перегрузку с `sys_graphics`.

## Шаг 5. `font.hlsl` — то, чего нет в форке

Форк убрал шрифт, потому что текст ушёл на Fontslash. Здесь `CMPFont` жив.

`DRAWONCE` определён в `MPFont.h`. Обычный `DrawText` при этом макросе рисует `DrawPrimitiveUP` с `D3DFVF_FONT` (`XYZRHW`) и `SetVertexShader(NULL)`. Экранный UI-текст от перевода шейдера не изменится.

Шейдер реально связывается в двух местах `MPFont.cpp`:

- `DrawTextClip` — `GetFontVS()`, `GetFontVDecl()`, цвет в c8, восемь констант c9..c16, затем `_pVB->DrawSubset(0)`;
- `Draw3DText` — world в c0 (транспонированная), viewProj в c4, цвет в c8, двенадцать констант c9..c20, `DrawSubset(0)`.

Меш создаётся в `CMPFont` как `D3DFVF_3DFONT` (`XYZB1 | DIFFUSE | TEX1`), `TRIANGLEFAN`, 4 вершины. Вес вершины `w`:

```
mi.blend_seq[w].weight[0] = (float)w * 2;   // 0, 2, 4, 6
```

Декларация `ve_dec_font` этому соответствует: `POSITION` float3, `BLENDWEIGHT` float1, `COLOR`, `TEXCOORD` float2. Шейдер из вершины читает только вес. Позиция, цвет и UV вершины ASM не использует (`font.vsh` не делает `dcl_position`).

Текущий ASM:

```
a0.x = blendweight          // 0, 2, 4, 6
r0   = c[a0.x + 9]          // позиция: c9, c11, c13, c15
oPos = ViewProj * World * r0
oD0  = c8
oT0  = c[a0.x + 10].xy      // UV:     c10, c12, c14, c16
```

Запись в `DrawTextClip` и `Draw3DText` чередует pos/uv: c9 pos, c10 uv, c11 pos, c12 uv, … `Draw3DText` пишет до c20, но фан из четырёх вершин читает только c9..c16. Лишние константы безвредны.

HLSL, регистры те же:

```hlsl
float4x4 World    : register(c0);
float4x4 ViewProj : register(c4);
float4   Color    : register(c8);
float4   Data[12] : register(c9); // покрывает и c9..c16, и запись 3D-текста до c20

struct VS_IN {
    float index : BLENDWEIGHT;
};

struct VS_OUT {
    float4 pos     : POSITION;
    float4 diffuse : COLOR0;
    float2 uv      : TEXCOORD0;
};

VS_OUT main(VS_IN i) {
    VS_OUT o;
    int idx = (int)i.index;          // 0, 2, 4, 6; усечение как mov a0
    float4 localPos = Data[idx];
    o.pos     = mul(mul(localPos, World), ViewProj);
    o.diffuse = Color;
    o.uv      = Data[idx + 1].xy;
    return o;
}
```

`Data[12]`, а не `[8]`: запись `Draw3DText` доходит до c20, и массив должен покрывать объявленный диапазон, даже если четыре вершины читают только начало. Динамический индекс по вершинному атрибуту в `vs_3_0` собирается в `a0`. В `vs_2_0` такой индекс на большом массиве часто не компилируется. Это одна из причин общего профиля `vs_3_0`, вместе со `shadeeff`.

`MPFont.cpp` не менять: ни порядок констант, ни веса `w * 2`, ни FVF-путь `DRAWONCE`.

## Шаг 6. Файлы шейдеров

Положить в `Client/shader/dx9` (туда смотрит `PATH_TYPE_SHADER`):

- `static_skin.hlsl`
- `vs_pndt0.hlsl`
- `skinmesh.hlsl`
- `eff1.hlsl`, `eff2.hlsl`, `eff3.hlsl`, `eff4.hlsl`
- `shadeeff.hlsl`
- `minimap.hlsl`
- `font.hlsl`

Исходники кроме шрифта брать из форка `258472e`, с двумя правками по тексту комментариев: профиль в шапке писать `vs_3_0`, а `c0.w` описывать как `765.01` (`3 * 255 + эпсилон`), не как stride 3. Логику регистров не переписывать.

Старые `.vsh` в `Client/shader/dx9` не удалять: без `LW_USE_VS30` загрузчик открывает именно их. Не удалять корневые `Client/shader/*.vsh` и каталог `shader/dx8`.

`font9.vsh` нигде не открывается (`LoadTotalVShader` грузит `font.vsh` или, с директивой, `font.hlsl`). К переключателю он не подключается.

## Порядок работ

1. Починить HLSL-ветку `lwShaderMgr9` (профиль, макросы, текст ошибки). Пока никто не передаёт `VS_FILE_HLSL`, поведение игры не меняется. Собрать DX9 без `LW_USE_VS30`.
2. Добавить `static_skin.hlsl` и `vs_pndt0.hlsl`. В `LoadShader0` обернуть таблицу в `#if defined(LW_USE_VS30)`. Проверить сборку без директивы (старые `.vsh`) и с директивой: статическая геометрия, жёсткий скининг (предметы, крылья, оружие с 1..4 весами), скролл UV.
3. Добавить `skinmesh.hlsl`, так же обернуть шесть записей в `LoadShader1`. С директивой проверить персонажа: один вес и два веса, три режима текстурной анимации (если в сцене есть tt2/tt3). Без директивы тот же персонаж должен остаться на `skinmesh8_*.vsh`.
4. Обернуть DX9-ветку `LoadTotalVShader`: `eff1..4`, `shadeeff`, `minimap`. Проверить партиклы, тень под персонажем, иконки миникарты в обеих конфигурациях.
5. Добавить `font.hlsl` в ту же таблицу, слот `VSTU_FONT_E5`. С директивой проверить `Draw3DText` (имена над головами) и клип текста (`DrawTextClip`). Обычный HUD при `DRAWONCE` сравнить в обеих сборках: он шейдер не использует.
6. Раскомментировать `LW_USE_VS30` в `lwDirectX.h`, когда сцена с директивой совпала со сценой без неё. `.vsh` не удалять.

Каждый шаг — отдельный коммит. Откат — закомментировать `LW_USE_VS30` в `lwDirectX.h` и пересобрать движок.

## Проверка

Две пересборки движка при `LW_USE_DX9`: строка `LW_USE_VS30` в `lwDirectX.h` закомментирована, затем раскомментирована. Сначала кадр без директивы, затем тот же кадр с директивой. На карте с персонажем, эффектом, тенью и миникартой:

- персонаж не разъезжается по костям и не чернеет (палитра c21 и `c0.w`);
- направленный свет с той же стороны, что до перехода;
- предмет с несколькими весами (pb2/pb3) не схлопывается в одну кость — это проверка свизла `zyxw`;
- UV-анимация на меше и на персонаже не поехала относительно старого кадра;
- партикл eff1/eff3/eff4 берёт UV углов квада из c9..c12, eff2 не теряет свой UV;
- пятно shade на земле на месте, не в нуле;
- иконка миникарты на своём кваде;
- 3D-текст и обрезанный текст читаемы, обычный текст HUD не изменился;
- в логе нет `D3DXCompileShader` error buffer;
- устройство с SM2 (если есть где взять) показывает ошибку капсов, а не молчаливый чёрный экран.

Сравнивать две конфигурации на той же позиции, а не новый кадр с воспоминанием о старом. Регистровый контракт либо совпадает побитово по смыслу, либо сцена сразу видимо ломается. Промежуточного «чуть-чуть не тот свет» быть не должно, кроме уже существующего сдвига UV-матрицы c7/c8 у `vs_pndt0`. Сборка без директивы после включения HLSL-файлов обязана совпадать с собой до шага 2: таблицы ASM под `#else` не меняются.

## Чего не делать в этом переходе

- Не удалять шрифтовый тип, декларацию, `GetFontVS` и не сдвигать индексы `_vecVDecl`.
- Не удалять `.vsh` из `Client/shader/dx9` и не делать выбор шейдера в рантайме. Переключатель — только `LW_USE_VS30` в `lwDirectX.h`; таблицы загрузки его читают, в `.cpp` и в `.vcxproj` дефайн не дублировать.
- Не переводить DX8 и не удалять `shader\dx8` и корневые `.vsh`.
- Не переносить вырезание SkyDoom, `terrain.hlsl`, `xyz_normal_*.hlsl`, `eff.fx`, sqlite.
- Не пересаживать меши на `ID3DXConstantTable` и имена `mat_viewproj` / `mat_bonepallette`.
- Не менять `MPFont.cpp`, веса вершин и `DRAWONCE`.
- Не поднимать палитру костей в шагах 1–6: там `BV[75]` и 25 костей, как у текущих `.vsh`. Увеличение лимита — отдельный раздел ниже, после того как сцена на `vs_3_0` совпала со старой.
- Не добавлять 3- и 4-весные слоты `VSTU_SKINMESH2/3`.
- Не компилировать эти шейдеры в `ps_*` и не смешивать `vs_3_0` с `ps_1_x` / `ps_2_0`.

## Лимит костей

Палитра остаётся в константных регистрах. Меш длиннее потолка одного draw режется на бакеты. Текстура с матрицами костей не делается: vertex texture fetch на этом пути нет.

78 — не текущий лимит. Это максимум одного бакета в константном файле `vs_3_0`, если палитра по-прежнему начинается с c21.

Сейчас меш адресует 25 костей. Три независимых числа:

| Где | Число | Что это |
|---|---|---|
| `skinmesh8_*.vsh`, `pu4nt0_ld.vsh` и соседние `pb*u4nt0_ld.vsh` | `BV[75]` с c21, в ASM `c[a0.x + 21]` | 75 регистров / 3 строки на кость = **25 костей**. Индекс 25 уже читает 76-й регистр массива, которого в объявлении нет. |
| `LW_MAX_BONE_NUM` в `lwITypes.h` | 25 | Размер `bone_index_seq` только у старых структур `lwMeshInfo_0000` и аналогов в `lwExpObj.h`. Живой `lwMeshInfo` держит `DWORD* bone_index_seq` и `bone_index_num` из файла без этого потолка. |
| `lwxRenderCtrlVSVertexBlend_dx8::BeginSet` | буфер `float[50 * 12]`, при `bone_num > 50` хвост отбрасывается | Залив в c21 режет палитру на **50** костей. Это больше, чем шейдер умеет прочитать, и меньше 78. |

Откуда 25. У `vs_1_1` всего 96 констант, c0..c95. Палитра с c21 занимает c21..c95 — ровно 75 регистров и 25 костей. Текущие `vs_2_x`-листинги сохранили тот же `BV[75]`.

Откуда 78. У `vs_3_0` минимум 256 констант, c0..c255. С c21 свободно 235 регистров. `235 / 3 = 78` кости и один регистр в остатке (c255). UV-матрицы сидят на c8, c12 и c16, то есть до палитры, и эти 78 не отъедают. Потолок бакета на устройстве — `(Caps.MaxVertexShaderConst - 21) / 3`, а не зашитые 78: если драйвер отдал больше 256 констант, бакет может быть длиннее. Если констант меньше 256, формула сама даст меньший бакет, и нарезка подстроится.

Как палитра собирается. `lwAnimCtrlObjBone::UpdateObject` для меша с `bone_index_num > 0` копирует в локальный массив матрицы скелета по `bone_index_seq[i]`. В вершину записан номер слота этой локальной палитры, не номер кости скелета. Шейдер умножает байт `D3DCOLOR` (0..1) на `c0.w = 765.01` и получает регистр `слот * 3`. Скелет сам по себе может быть длиннее палитры меша: в палитру попадает только список `bone_index_seq`. Байт индекса называет слот 0..255, поэтому один бакет в этом формате вершины не длиннее 256 слотов. Константный потолок 78 укладывается в байт, формат вершины не меняется.

Раздел выполняется только при `LW_USE_VS30` и только после шагов 1–6, когда сцена на `vs_3_0` с 25 костями совпала со старой. Сборка без директивы остаётся на `BV[75]` и на обрезке в 50. `c0.w` не меняется.

Шейдеры те же: `skinmesh.hlsl` и `static_skin.hlsl`, массив палитры длиннее. Заливку правит `lwxRenderCtrlVSVertexBlend_dx8::BeginSet`, тот контроллер, который пишет c21. Именной `ID3DXConstantTable`-контроллер не трогать.

### Бакет

Под `LW_USE_VS30` массив становится `BV[N * 3]` на c21, где `N = (MaxVertexShaderConst - 21) / 3`. На типичной SM3-карте `N = 78`, то есть `BV[234]` и регистры c21..c254. Буфер заливки — `N * 12` float. Обрезку `bone_num > 50` снять. Меш, у которого `bone_index_num` не больше `N`, рисуется как сейчас, одним вызовом.

Меш длиннее `N` режется на бакеты. Бакет — один draw с собственной палитрой не длиннее `N` и со своими локальными индексами в вершинах.

Правило нарезки, один раз при загрузке меша, не каждый кадр:

- грань целиком попадает в бакет, если объединение костей трёх вершин вместе с уже набранными костями бакета не превышает `N`;
- иначе грань открывает следующий бакет;
- вершина, которую просят два бакета, дублируется: в каждом бакете у неё свой локальный слот. Общий VB с исходными индексами оставить нельзя, шейдер смотрит только в палитру текущего draw;
- на выходе у бакета свой список `bone_index_seq`, свой диапазон индексов и VB, в котором blend-индексы уже перенумерованы в `0 .. N-1`.

На кадре `BeginSet` заливает палитру бакета в c21 и рисует его. Число draw равно числу бакетов. Для меша на 25–78 костей на обычной SM3-карте это по-прежнему один draw.

`LW_MAX_BONE_NUM` в старых структурах файла не менять.

### Шаги

1. После стабильного шага 6 замерить на живых моделях `bone_index_num`. Если ни один меш не длиннее 25, палитру всё равно поднять до `N`: обрезка на 50 и `BV[75]` расходятся уже сейчас, и следующий меш длиннее 25 не должен молча терять кости. Нарезку бакетов писать в том же изменении, даже если на текущих данных она не срабатывает.
2. Под `LW_USE_VS30` поднять константную палитру до `N`: `BV[N * 3]` в `skinmesh.hlsl` и `static_skin.hlsl`, буфер в `BeginSet` того же размера, убрать обрезку на 50. Сборка без директивы эту ветку не компилирует. Проверить прежнего персонажа: 25 костей должны лечь в начало той же c21 и выглядеть как до шага.
3. Нарезка бакетов при загрузке меша, если `bone_index_num > N`. Дублировать только вершины на границе бакетов, индексы в VB перенумеровать в слоты бакета. На кадре заливать палитру бакета и рисовать бакеты по очереди. Проверка: меш короче `N` — один draw; искусственно урезанный потолок (например 8) на том же персонаже — несколько draw и та же картинка.
