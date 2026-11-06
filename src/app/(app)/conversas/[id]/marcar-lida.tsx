"use client";
import { useEffect } from "react";
import { marcarLida } from "../actions";

export function MarcarLida({ id, quando }: { id: string; quando: number }) {
  useEffect(() => { if (quando > 0) void marcarLida(id); }, [id, quando]);
  return null;
}
