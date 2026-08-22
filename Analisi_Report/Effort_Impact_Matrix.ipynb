import pandas as pd
import matplotlib.pyplot as plt
!pip install adjustText
from adjustText import adjust_text

# path csv di report post-esecuzione framework
CSV_PATH = "cis_[ambiente]_scoring_report_example.csv"
BETA = 0.7

# lettura csv e formattazione
df = pd.read_csv(CSV_PATH, encoding="utf-8-sig")
for col in ["E_i", "E_norm"]:
    df[col] = df[col].astype(str).str.replace(",", ".").astype(float)

nc = df[df["Status"] == "NON-COMPLIANT"].copy()

# Raggruppamento controlli con (E_norm, impatto) identici
grouped = (
    nc.groupby(["E_norm", "NonCompliant"])["ID"]
    .apply(lambda ids: ", ".join(sorted(ids)))
    .reset_index()
)

x = grouped["E_norm"]
y = grouped["NonCompliant"]
labels = grouped["ID"]

x_soglia = BETA
y_soglia = nc["NonCompliant"].median()

def colore(xi, yi):
    if xi < x_soglia and yi >= y_soglia:
        return "#1D9E75"
    elif xi >= x_soglia and yi >= y_soglia:
        return "#E24B4A"
    elif xi < x_soglia and yi < y_soglia:
        return "#888780"
    else:
        return "#EF9F27"

colors = [colore(xi, yi) for xi, yi in zip(x, y)]

# costruzione grafico e plot
fig, ax = plt.subplots(figsize=(10, 7))
ax.scatter(x, y, c=colors, s=80, edgecolors="white", linewidth=0.6, zorder=3)

ax.axvline(x_soglia, color="gray", linestyle="--", linewidth=0.8, zorder=1)
ax.axhline(y_soglia, color="gray", linestyle="--", linewidth=0.8, zorder=1)

# Le etichette vengono posizionate automaticamente senza sovrapporsi,
# con una sottile linea di collegamento al punto reale se necessario.
texts = [
    ax.text(xi, yi, lab, fontsize=7)
    for xi, yi, lab in zip(x, y, labels)
]
adjust_text(
    texts, ax=ax,
    arrowprops=dict(arrowstyle="-", color="gray", lw=0.5),
    expand_points=(1.3, 1.3),
)

ax.set_xlabel("Effort ($E_{norm}$)")
ax.set_ylabel("Impatto (n. oggetti non conformi)")
ax.set_title("Matrice Effort vs Impatto")
ax.set_xlim(-0.05, 1.05)

plt.tight_layout()
plt.savefig("matrice_effort_impatto.png", dpi=300)
plt.show()