"""Assignment 10 · a results page for my variant-calling runs.

Run from the top of the repository:
    python3 dashboard/app.py runs.db          # then open http://127.0.0.1:8050
    python3 dashboard/app.py runs.db 8051     # on another port
"""
import os
import sqlite3
import sys
from urllib.parse import parse_qs

import pandas as pd
import dash_ag_grid as dag
import plotly.express as px
from dash import Dash, dcc, html
from dash import Input, Output, State, callback, ctx

DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050

HERE = os.path.dirname(os.path.abspath(__file__))
Q1 = os.path.join(HERE, "..", "db", "queries", "q1.sql")

TRANSITIONS = {"AG", "GA", "CT", "TC"}

# The plots that a click narrows the sites table by, and the column each one counts
COUNT_PLOTS = {"plot-filter": "filter", "plot-type": "type", "plot-titv": "titv"}


# ---------------------------------------------------------------- the data
def query(sql, params=()):
    """One SQL statement, on a connection of its own (Dash runs callbacks in threads)."""
    con = sqlite3.connect(DB)
    rows = pd.read_sql_query(sql, con, params=params)
    con.close()
    return rows


def site_type(ref, alt):
    if "," in alt:
        return "multiallelic"
    if len(ref) == 1 and len(alt) == 1:
        return "SNP"
    return "indel"


def titv(ref, alt):
    return "transition" if (ref + alt).upper() in TRANSITIONS else "transversion"


def run_sites(run_id):
    """The run's sites, with two columns computed from ref and alt."""
    sites = query("""
        SELECT chrom, pos, ref, alt, qual, filter
        FROM variants
        WHERE run_id = ?
        ORDER BY chrom, pos""", (run_id,))
    sites["type"] = [site_type(r, a) for r, a in zip(sites["ref"], sites["alt"])]
    sites["titv"] = [titv(r, a) if t == "SNP" else None
                     for r, a, t in zip(sites["ref"], sites["alt"], sites["type"])]
    return sites


def count_bar(sites, column, title):
    """A bar for each value of the column, as tall as its number of sites."""
    counts = sites[column].value_counts().reset_index()
    counts.columns = [column, "sites"]
    return px.bar(counts, x=column, y="sites", title=title)


def grid(grid_id, rows, columns):
    return dag.AgGrid(id=grid_id,
                      rowData=rows,
                      columnDefs=[{"field": c} for c in columns],
                      columnSize="sizeToFit")


# ---------------------------------------------------------------- the two pages
def runs_page():
    with open(Q1) as f:
        runs = query(f.read())
    links = [html.Li(dcc.Link(r, href=f"/results?run={r}")) for r in runs["run_id"]]
    return [html.H1("My variant-calling runs"),
            html.P(f"Database: {DB}"),
            html.Ul(links),
            grid("runs-table", runs.to_dict("records"), runs.columns)]


def results_page(run_id):
    samples = query("""
        SELECT run_samples.sample_id, run_samples.condition,
               samples.phenotype, samples.is_synthetic_phenotype
        FROM run_samples
        LEFT JOIN samples ON samples.sample_id = run_samples.sample_id
        WHERE run_samples.run_id = ?
        ORDER BY run_samples.sample_id""", (run_id,))

    sites = run_sites(run_id)
    snps = sites[sites["type"] == "SNP"]

    plot_filter = count_bar(sites, "filter",
                            "How many sites passed, and why did the others fail?")
    plot_qual = px.histogram(sites, x="qual", title="How confident are the calls?")
    plot_position = px.histogram(sites, x="pos", title="Where along the region are the sites?")
    plot_type = count_bar(sites, "type", "How many SNPs, indels and multiallelic sites?")
    plot_titv = count_bar(snps, "titv",
                          "Among SNPs, how many transitions and transversions?")

    return [dcc.Link("← all runs", href="/"),
            html.H1(f"Results of {run_id}"),
            html.H2("Samples"),
            html.P(html.B("The phenotypes in this cohort are made up for the course: "
                          "is_synthetic_phenotype marks them.")),
            grid("samples-table", samples.to_dict("records"),
                 ["sample_id", "condition", "phenotype", "is_synthetic_phenotype"]),
            html.H2("Sites"),
            dcc.Graph(id="plot-filter", figure=plot_filter),
            dcc.Graph(id="plot-type", figure=plot_type),
            dcc.Graph(id="plot-titv", figure=plot_titv),
            dcc.Graph(id="plot-qual", figure=plot_qual),
            dcc.Graph(id="plot-position", figure=plot_position),
            html.P("Click a bar of the filter, type or Ti/Tv plot to keep only its sites."),
            grid("sites-table", [], ["chrom", "pos", "ref", "alt", "qual", "filter"])]


# ---------------------------------------------------------------- the layout
app = Dash(__name__, suppress_callback_exceptions=True)
app.layout = [dcc.Location(id="url"), html.Div(id="page", children=[])]


# ---------------------------------------------------------------- the callbacks
@callback(Output("page", "children"),
          Input("url", "pathname"), Input("url", "search"))
def draw_page(pathname, search):
    if pathname == "/results":
        run = parse_qs((search or "").lstrip("?")).get("run")
        if run:
            return results_page(run[0])
        return [html.H1("No run in the address"), dcc.Link("← all runs", href="/")]
    return runs_page()


@callback(Output("sites-table", "rowData"),
          Input("plot-filter", "clickData"),
          Input("plot-type", "clickData"),
          Input("plot-titv", "clickData"),
          State("url", "search"))
def narrow_sites(filter_click, type_click, titv_click, search):
    run_id = parse_qs((search or "").lstrip("?"))["run"][0]
    sites = run_sites(run_id)

    clicks = {"plot-filter": filter_click, "plot-type": type_click, "plot-titv": titv_click}
    plot = ctx.triggered_id
    if plot in clicks and clicks[plot] is not None:
        point = clicks[plot]["points"][0]
        value = point.get("label", point.get("x"))
        sites = sites[sites[COUNT_PLOTS[plot]] == value]

    return sites[["chrom", "pos", "ref", "alt", "qual", "filter"]].to_dict("records")


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
