import sys
from base64 import b64decode
from pathlib import Path
import os
from gvm.protocols.gmp import Gmp
from gvm.xml import pretty_print
from datetime import datetime


def get_latest_report_id_from_task(gmp: Gmp, task_name: str) -> str:
    response = gmp.get_tasks(filter_string=f"name={task_name}", details=True)

    for task in response.findall("task"):
        name = task.findtext("name")
        if name and name.strip() == task_name:
            report_element = task.find("last_report/report")
            if report_element is not None:
                report_id = report_element.get("id")
                if report_id:
                    return report_id

    print(f"❌ No se pudo encontrar el último reporte para la tarea '{task_name}'", file=sys.stderr)
    sys.exit(1)


def export_report_as_xml(gmp: Gmp, report_id: str, output_file: str):
    # xml_report_format_id puede ser ajustado según el tipo de reporte que necesites
    xml_report_format_id = "a994b278-1f62-11e1-96ac-406186ea4fc5"

    response = gmp.get_report(
        report_id=report_id,
        report_format_id=xml_report_format_id,
        ignore_pagination=True,
        details=True,
    )

    report_element = response.find("report")
    pretty_print(report_element)

    content = report_element.find("report_format").tail if report_element is not None else None

    if not content:
        sys.exit(1)

    binary_xml = b64decode(content.encode("ascii"))
    Path(output_file).expanduser().write_bytes(binary_xml)


def main(gmp: Gmp, args):
    task_name = os.environ.get("TASK_NAME")
    if not task_name:
        print("❌ Falta la variable de entorno 'TASK_NAME'!", file=sys.stderr)
        sys.exit(1)

    date = datetime.now().strftime("%d-%m")
    output_file = f"/var/log/reportes/reporte-{task_name}_{date}.xml"

    report_id = get_latest_report_id_from_task(gmp, task_name)

    export_report_as_xml(gmp, report_id, output_file)


if __name__ == "__gmp__":
    main(gmp, None)





