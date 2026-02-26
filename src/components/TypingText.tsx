import React from 'react';
import { useTypingEffect } from '../hooks/useTypingEffect';
interface TypingTextProps {
  text: string;
  speed?: number;
  delay?: number;
  className?: string;
  cursor?: boolean;
}
export function TypingText({
  text,
  speed = 30,
  delay = 0,
  className = '',
  cursor = true
}: TypingTextProps) {
  const { displayedText, isComplete } = useTypingEffect(text, speed, delay);
  return (
    <span className={className}>
      {displayedText}
      {cursor && !isComplete &&
      <span className="cursor-blink text-terminal-accent">_</span>
      }
    </span>);

}