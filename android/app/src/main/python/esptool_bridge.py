import io
import json
import shlex
import traceback
from contextlib import redirect_stderr, redirect_stdout

from android_serial import install_android_pyserial


class EsptoolCancelled(Exception):
    pass


def _get_callback_attr(callback, *names):
    for name in names:
        try:
            attr = getattr(callback, name)
        except AttributeError:
            continue
        return attr
    return None


def _callback_is_cancelled(callback):
    if callback is None:
        return False

    attr = _get_callback_attr(
        callback,
        "shouldCancel",
        "isCancelled",
        "is_cancelled",
        "cancelled",
    )
    if attr is None:
        return False

    if callable(attr):
        return bool(attr())

    return bool(attr)


def _callback_emit_output(callback, text):
    if callback is None or not text:
        return

    attr = _get_callback_attr(
        callback,
        "emitOutput",
        "onOutput",
        "on_output",
        "accept",
    )
    if callable(attr):
        attr(text)
        return

    if callable(callback):
        callback(text)


class ForwardingBuffer:
    def __init__(self, output, callback=None):
        self._output = output
        self._callback = callback

    def write(self, text):
        if not text:
            return 0
        if not isinstance(text, str):
            text = str(text)
        if _callback_is_cancelled(self._callback):
            raise EsptoolCancelled()
        self._output.write(text)
        if self._callback is not None:
            _callback_emit_output(self._callback, text)
            if _callback_is_cancelled(self._callback):
                raise EsptoolCancelled()
        return len(text)

    def flush(self):
        return None


def _to_python_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)

    size = getattr(value, "size", None)
    getter = getattr(value, "get", None)
    if callable(size) and callable(getter):
        return [getter(index) for index in range(size())]

    iterator_factory = getattr(value, "iterator", None)
    if callable(iterator_factory):
        iterator = iterator_factory()
        items = []
        while iterator.hasNext():
            items.append(iterator.next())
        return items

    to_array = getattr(value, "toArray", None)
    if callable(to_array):
        array = to_array()
        try:
            return [array[index] for index in range(len(array))]
        except TypeError:
            pass

    try:
        return list(value)
    except TypeError:
        return [value]


def _normalize_exit_code(code):
    if code is None:
        return 0
    if isinstance(code, bool):
        return 0 if code else 1
    if isinstance(code, int):
        return code
    return 1


def run_esptool(context, arguments, callback=None):
    output = io.StringIO()
    exit_code = 0
    cancelled = False

    try:
        install_android_pyserial(context)
        import esptool

        if isinstance(arguments, str):
            stripped_arguments = arguments.strip()
            if stripped_arguments.startswith("["):
                decoded_arguments = json.loads(stripped_arguments)
                argv = [str(arg) for arg in decoded_arguments]
            else:
                argv = shlex.split(arguments)
        else:
            argv = [str(arg) for arg in _to_python_list(arguments)]

        stream = ForwardingBuffer(output, callback)
        with redirect_stdout(stream), redirect_stderr(stream):
            try:
                esptool.main(argv)
            except SystemExit as exc:
                exit_code = _normalize_exit_code(exc.code)
            except EsptoolCancelled:
                cancelled = True
                exit_code = 1
    except Exception:
        error = traceback.format_exc()
        output.write(error)
        if callback is not None:
            _callback_emit_output(callback, error)
        exit_code = 1

    return json.dumps(
        {
            "success": exit_code == 0 and not cancelled,
            "output": output.getvalue().strip(),
            "cancelled": cancelled,
        }
    )
