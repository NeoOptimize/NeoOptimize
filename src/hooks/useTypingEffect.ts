import { useState, useEffect } from 'react';

export function useTypingEffect(
text: string,
speed: number = 30,
startDelay: number = 0)
{
  const [displayedText, setDisplayedText] = useState('');
  const [isComplete, setIsComplete] = useState(false);

  useEffect(() => {
    let timeoutId: NodeJS.Timeout;
    let currentIndex = 0;

    // Reset state when text changes
    setDisplayedText('');
    setIsComplete(false);

    const startTyping = () => {
      const typeChar = () => {
        if (currentIndex < text.length) {
          setDisplayedText(text.slice(0, currentIndex + 1));
          currentIndex++;
          timeoutId = setTimeout(typeChar, speed);
        } else {
          setIsComplete(true);
        }
      };
      typeChar();
    };

    const initialTimeout = setTimeout(startTyping, startDelay);

    return () => {
      clearTimeout(timeoutId);
      clearTimeout(initialTimeout);
    };
  }, [text, speed, startDelay]);

  return { displayedText, isComplete };
}